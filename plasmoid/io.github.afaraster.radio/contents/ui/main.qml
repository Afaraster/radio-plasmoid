// 极简电台挂件 —— 可编辑标签页 + 关键词/筛选搜索。
// 播放走 QtMultimedia（Debian 的 Qt 6.8 用 FFmpeg 后端），搜索是一次 XMLHttpRequest。
// 全部状态存在 plasmoid.configuration（见 contents/config/main.xml）。
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtMultimedia
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color dimColor: Kirigami.Theme.disabledTextColor
    readonly property color warnColor: Kirigami.Theme.negativeTextColor
    readonly property string directoryApi: "https://de1.api.radio-browser.info/json/stations/search"
    readonly property int searchLimit: 60
    readonly property int historyLimit: 6

    // ---- 持久化状态 ----
    property var favList: []
    property var histList: []
    property var tabs: []                 // [{ name, stations: [{name,url}] }]
    property var lastStation: null
    property int activeTabIndex: 0
    property string activeView: "tabs"    // tabs | fav | search
    property string returnView: "tabs"    // 清空搜索时回到哪里
    property int returnTabIndex: 0

    // ---- 搜索筛选 ----
    property string countryFilter: ""
    property string tagFilter: ""

    // ---- 界面状态 ----
    property bool expanded: false
    property string statusText: "未播放"
    property string errText: ""
    property string nowPlaying: ""
    property bool searching: false
    property var _xhr: null
    property bool showNewTab: false
    property string pendingTabAction: ""  // "" | add | move
    property var ctxTarget: null          // 右键的频道 {name,url}
    property int ctxTabIndex: -1          // 右键的标签序号

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    // 兜底：Qt 会记住组件初始化时的默认输出设备（开机时蓝牙往往还没连上），
    // 之后创建音频流时显式指定它，声音就进了内置声卡。
    // 播放后一秒调用一次脚本，把 plasmashell 的流拨回系统默认设备。
    P5Support.DataSource {
        id: routeFix
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            routeFix.disconnectSource(sourceName);
            console.log("[radio] " + String(data["stdout"] || "").trim());
        }
    }

    Timer {
        id: routeFixTimer
        interval: 1500
        repeat: false
        onTriggered: routeFix.connectSource("sh -c \"exec $HOME/.local/bin/radio-follow-default\"")
    }

    ListModel { id: favModel }
    ListModel { id: searchModel }
    ListModel { id: tabModel }

    property var currentModel: activeView === "fav" ? favModel
                             : activeView === "search" ? searchModel
                             : tabModel

    // 默认标签（首次运行时写入配置，之后完全由用户增删改）
    function defaultTabs() {
        return [
            { "name": "新闻", "stations": [
                { "name": "CNR-1 中国之声", "url": "https://lhttp.qtfm.cn/live/15318317/64k.mp3" },
                { "name": "上海新闻广播", "url": "http://lhttp.qingting.fm/live/270/64k.mp3" },
                { "name": "北京新闻广播", "url": "https://lhttp.qtfm.cn/live/339/64k.mp3" },
                { "name": "广东新闻广播", "url": "https://lhttp.qtfm.cn/live/1254/64k.mp3" },
                { "name": "国际新闻", "url": "https://lhttp.qtfm.cn/live/20500172/64k.mp3" }
            ] },
            { "name": "音乐", "stations": [
                { "name": "RadioArt 独奏钢琴", "url": "http://live.radioart.com/fSolo_piano.mp3" },
                { "name": "Epic Piano 钢琴氛围", "url": "https://stream.epic-piano.com/chillout-piano?ref=radiobrowser" },
                { "name": "Nightride Chillsynth", "url": "https://stream.nightride.fm/chillsynth.mp3" },
                { "name": "Radio Paradise Main", "url": "https://stream.radioparadise.com/aac-128" },
                { "name": "Radio Paradise Mellow", "url": "https://stream.radioparadise.com/mellow-320" },
                { "name": "Nightwave Plaza", "url": "http://radio.plaza.one/opus" },
                { "name": "I Love Music · Chillhop", "url": "https://ilm.stream12.radiohost.de/ilm_ilovechillhop_mp3-192?upd-meta&upd-scheme=https" },
                { "name": "WALM 2 古典 HD", "url": "https://icecast.walmradio.com:8443/walm2" },
                { "name": "EVE Radio", "url": "https://eve.gamingnow.net:8010/erweb.mp3" }
            ] }
        ];
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audioOut
            // 不指定 device：每次 start() 取当时的系统默认输出；热切换交给
            // PulseAudio 的 module-switch-on-connect + restore_device=false。
            volume: 0.8
        }

        onPlaybackStateChanged: function (state) {
            console.log("[radio] playbackState -> " + state);
            if (state === MediaPlayer.PlayingState)
                root.statusText = "播放中";
            else if (state === MediaPlayer.PausedState)
                root.statusText = "已暂停";
            else
                root.statusText = "已停止";
        }

        onMediaStatusChanged: function (status) {
            if (status === MediaPlayer.LoadingMedia)
                root.statusText = "连接中…";
            else if (status === MediaPlayer.BufferingMedia)
                root.statusText = "缓冲中…";
            else if (status === MediaPlayer.InvalidMedia)
                root.statusText = "无法播放";
        }

        onErrorOccurred: function (error, errorString) {
            root.errText = "播放错误：" + errorString;
            root.statusText = "无法播放";
        }
    }

    // ---------- 配置 ----------

    function persist() {
        plasmoid.configuration.favorites = JSON.stringify(root.favList);
        plasmoid.configuration.history = JSON.stringify(root.histList);
        plasmoid.configuration.tabs = JSON.stringify(root.tabs);
        plasmoid.configuration.lastStation = root.lastStation ? JSON.stringify(root.lastStation) : "";
        plasmoid.configuration.lastTab = root.activeView === "tabs"
                ? ("tabs:" + root.activeTabIndex) : root.activeView;
        if (typeof plasmoid.configuration.writeConfig === "function")
            plasmoid.configuration.writeConfig();
    }

    function loadConfig() {
        try { root.favList = JSON.parse(plasmoid.configuration.favorites || "[]") || []; }
        catch (e) { root.favList = []; }
        try { root.histList = JSON.parse(plasmoid.configuration.history || "[]") || []; }
        catch (e) { root.histList = []; }
        try {
            var t = JSON.parse(plasmoid.configuration.tabs || "[]");
            root.tabs = (Array.isArray(t) && t.length > 0) ? t : root.defaultTabs();
        } catch (e) {
            root.tabs = root.defaultTabs();
        }
        try {
            var ls = plasmoid.configuration.lastStation;
            if (ls && ls.length > 0) {
                var parsed = JSON.parse(ls);
                if (parsed && parsed.url)
                    root.lastStation = parsed;
            }
        } catch (e) { root.lastStation = null; }
        if (root.lastStation)
            root.nowPlaying = root.lastStation.name;

        // 恢复上次停留的视图
        var lt = String(plasmoid.configuration.lastTab || "tabs:0");
        if (lt.indexOf("tabs:") === 0) {
            var idx = parseInt(lt.substring(5), 10);
            root.activeView = "tabs";
            root.activeTabIndex = (isNaN(idx) || idx < 0 || idx >= root.tabs.length) ? 0 : idx;
        } else if (lt === "fav") {
            root.activeView = "fav";
        } else {
            root.activeView = "tabs";
            root.activeTabIndex = 0;
        }
        root.returnView = root.activeView === "search" ? "tabs" : root.activeView;
        root.returnTabIndex = root.activeTabIndex;

        root.rebuildFavModel();
        root.rebuildTabModel();
        console.log("[radio] loaded tabs=" + root.tabs.length
                    + " favorites=" + root.favList.length
                    + " lastStation=" + (root.lastStation ? root.lastStation.name : "none")
                    + " view=" + root.activeView + ":" + root.activeTabIndex);
    }

    Component.onCompleted: root.loadConfig()

    // ---------- 收藏 ----------

    function isFav(name, url) {
        for (var i = 0; i < root.favList.length; i++)
            if (root.favList[i].url === url)
                return true;
        return false;
    }

    function rebuildFavModel() {
        favModel.clear();
        for (var i = 0; i < root.favList.length; i++)
            favModel.append({ "name": root.favList[i].name, "url": root.favList[i].url });
    }

    function toggleFav(name, url) {
        var next = [], found = false;
        for (var i = 0; i < root.favList.length; i++) {
            if (root.favList[i].url === url) { found = true; continue; }
            next.push(root.favList[i]);
        }
        if (!found)
            next.push({ "name": name, "url": url });
        root.favList = next;
        root.rebuildFavModel();
        root.persist();
    }

    // ---------- 标签 ----------

    function rebuildTabModel() {
        tabModel.clear();
        var t = root.tabs[root.activeTabIndex];
        if (!t)
            return;
        for (var i = 0; i < t.stations.length; i++)
            tabModel.append({ "name": t.stations[i].name, "url": t.stations[i].url });
    }

    function openTab(idx) {
        root.activeTabIndex = idx;
        root.activeView = "tabs";
        root.errText = "";
        if (idx !== root.returnTabIndex || root.returnView === "tabs") {
            root.returnView = "tabs";
            root.returnTabIndex = idx;
        }
        root.rebuildTabModel();
        root.persist();
    }

    function openFav() {
        root.activeView = "fav";
        root.returnView = "fav";
        root.errText = "";
        root.persist();
    }

    function createTab(name) {
        name = String(name || "").trim();
        if (name.length === 0)
            return;
        var tabs = root.tabs.slice();
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].name === name)
                return;
        tabs.push({ "name": name, "stations": [] });
        root.tabs = tabs;
        root.persist();
        root.openTab(tabs.length - 1);
    }

    function deleteTab(idx) {
        if (idx < 0 || idx >= root.tabs.length)
            return;
        var tabs = root.tabs.slice();
        tabs.splice(idx, 1);
        root.tabs = tabs;
        if (root.activeView === "tabs") {
            root.activeTabIndex = Math.max(0, Math.min(root.activeTabIndex, tabs.length - 1));
            root.rebuildTabModel();
        }
        root.persist();
    }

    function addToTab(name, url, tabName) {
        var tabs = root.tabs.slice();
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].name !== tabName)
                continue;
            var arr = tabs[i].stations.slice();
            for (var j = 0; j < arr.length; j++)
                if (arr[j].url === url)
                    return;
            arr.push({ "name": name, "url": url });
            tabs[i] = { "name": tabs[i].name, "stations": arr };
            root.tabs = tabs;
            root.persist();
            root.rebuildTabModel();
            return;
        }
    }

    function removeFromTab(tabIdx, url) {
        var tabs = root.tabs.slice();
        var t = tabs[tabIdx];
        if (!t)
            return;
        var keep = [];
        for (var i = 0; i < t.stations.length; i++)
            if (t.stations[i].url !== url)
                keep.push(t.stations[i]);
        tabs[tabIdx] = { "name": t.name, "stations": keep };
        root.tabs = tabs;
        root.persist();
        root.rebuildTabModel();
    }

    function moveToTab(name, url, fromIdx, tabName) {
        root.addToTab(name, url, tabName);
        root.removeFromTab(fromIdx, url);
    }

    function applyTabAction(tabName) {
        if (!root.ctxTarget) {
            root.pendingTabAction = "";
            return;
        }
        if (root.pendingTabAction === "add")
            root.addToTab(root.ctxTarget.name, root.ctxTarget.url, tabName);
        else if (root.pendingTabAction === "move")
            root.moveToTab(root.ctxTarget.name, root.ctxTarget.url, root.ctxTabIndex, tabName);
        root.pendingTabAction = "";
    }

    // ---------- 播放 ----------

    // Qt 会记住组件初始化那一刻的默认输出设备，而 plasmashell 启动通常早于蓝牙连接，
    // 于是流被显式送到内置声卡。每次播放前重新取一次系统默认设备。
    function refreshOutputDevice() {
        var d = MediaDevices.defaultAudioOutput;
        var cur = audioOut.device ? audioOut.device.description : "none";
        console.log("[radio] devices: default=" + (d ? d.description : "undefined")
                    + " | current=" + cur);
        if (d && d.description !== cur) {
            audioOut.device = d;
            console.log("[radio] audioOutput.device -> " + d.description);
        }
    }

    function playStation(name, url) {
        console.log("[radio] playStation name=" + name + " url=" + url
                    + " vol=" + audioOut.volume
                    + " device=" + (audioOut.device ? audioOut.device.description : "none"));
        root.errText = "";
        root.nowPlaying = name;
        root.lastStation = { "name": name, "url": url };
        root.persist();
        root.refreshOutputDevice();
        player.stop();
        player.source = url;
        player.play();
        routeFixTimer.restart();
        console.log("[radio] after play -> state=" + player.playbackState
                    + " mediaStatus=" + player.mediaStatus
                    + " source=" + player.source
                    + " error=" + player.errorString);
    }

    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause();
            return;
        }
        // 刚启动时 source 为空，用记住的台补上，重启后第一次点播放就能接着播
        root.refreshOutputDevice();
        if (player.source == "" && root.lastStation) {
            root.nowPlaying = root.lastStation.name;
            player.source = root.lastStation.url;
        }
        if (player.source != "") {
            player.play();
            routeFixTimer.restart();
        }
    }

    // ---------- 搜索 ----------

    function buildSearchUrl(text) {
        var params = ["limit=" + root.searchLimit, "hidebroken=true", "order=votes", "reverse=true"];
        if (text.length > 0)
            params.push("name=" + encodeURIComponent(text));
        if (root.countryFilter.length > 0)
            params.push("countrycode=" + encodeURIComponent(root.countryFilter));
        if (root.tagFilter.length > 0)
            params.push("tag=" + encodeURIComponent(root.tagFilter));
        return root.directoryApi + "?" + params.join("&");
    }

    function rememberQuery(text) {
        if (text.length === 0)
            return;
        var next = [text];
        for (var i = 0; i < root.histList.length && next.length < root.historyLimit; i++)
            if (root.histList[i] !== text)
                next.push(root.histList[i]);
        root.histList = next;
        root.persist();
    }

    // 清空搜索（输入框由调用方清，root 层看不到组件内的 id）
    function clearSearch() {
        root.countryFilter = "";
        root.tagFilter = "";
        root.errText = "";
        root.activeView = root.returnView === "search" ? "tabs" : root.returnView;
        root.activeTabIndex = root.returnTabIndex;
        root.rebuildTabModel();
        root.persist();
    }

    function doSearch(text) {
        text = String(text || "").trim();
        if (text.length === 0 && root.countryFilter.length === 0 && root.tagFilter.length === 0) {
            root.clearSearch();
            return;
        }
        if (root.searching)
            return;
        if (root.activeView !== "search") {
            root.returnView = root.activeView;
            root.returnTabIndex = root.activeTabIndex;
        }
        root.searching = true;
        root.errText = "";
        root.statusText = "正在搜索…";

        var xhr = root._xhr = new XMLHttpRequest();
        xhr.open("GET", root.buildSearchUrl(text));
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.searching = false;
            if (xhr.status !== 200) {
                root.errText = "目录请求失败：HTTP " + xhr.status;
                root.statusText = "搜索失败";
                return;
            }
            var rows;
            try { rows = JSON.parse(xhr.responseText); }
            catch (e) { root.errText = "结果解析失败：" + e; root.statusText = "搜索失败"; return; }
            searchModel.clear();
            var seen = [], n = 0;
            for (var i = 0; i < rows.length; i++) {
                var row = rows[i];
                var u = row.url_resolved || "";
                if (!u || row.hls === true || !row.stationuuid || !row.name)
                    continue;
                if (seen.indexOf(u) !== -1)
                    continue;
                seen.push(u);
                searchModel.append({ "name": String(row.name).trim(), "url": u });
                n++;
            }
            root.activeView = "search";
            root.rememberQuery(text);
            root.statusText = n > 0 ? ("找到 " + n + " 个电台") : "没有找到电台";
        };
        xhr.send();
    }

    toolTipMainText: "电台"
    toolTipSubText: root.nowPlaying.length > 0 ? (root.nowPlaying + "\n" + root.statusText) : root.statusText

    fullRepresentation: Item {
        // popup 的尺寸由这几项决定：implicit 给默认大小，
        // Layout.minimum* 防止 Plasma 把面板弹窗压成内容最小尺寸
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 30)
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 31)
        Layout.minimumWidth: Math.round(Kirigami.Units.gridUnit * 26)
        Layout.minimumHeight: Math.round(Kirigami.Units.gridUnit * 24)
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // ---- 搜索行 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "搜索电台：新闻 / jazz / house …"
                    onAccepted: root.doSearch(searchField.text)
                }
                QQC.Button {
                    text: root.searching ? "…" : "搜索"
                    enabled: !root.searching
                    onClicked: root.doSearch(searchField.text)
                }
                QQC.Button {
                    text: "✕"
                    implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.8)
                    onClicked: {
                        searchField.text = "";
                        root.clearSearch();
                    }
                }
            }

            // ---- 筛选行 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text { text: "筛选"; color: dimColor; font.pointSize: 8 }
                QQC.Button {
                    text: "中国"; checkable: true; checked: root.countryFilter === "CN"; font.pointSize: 8
                    onClicked: root.countryFilter = (root.countryFilter === "CN" ? "" : "CN")
                }
                QQC.Button {
                    text: "新闻"; checkable: true; checked: root.tagFilter === "news"; font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "news" ? "" : "news")
                }
                QQC.Button {
                    text: "音乐"; checkable: true; checked: root.tagFilter === "music"; font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "music" ? "" : "music")
                }
                QQC.Button {
                    text: "钢琴"; checkable: true; checked: root.tagFilter === "piano"; font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "piano" ? "" : "piano")
                }
                QQC.Button {
                    text: "爵士"; checkable: true; checked: root.tagFilter === "jazz"; font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "jazz" ? "" : "jazz")
                }
                Item { Layout.fillWidth: true }
            }

            // ---- 最近搜索 ----
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.histList.length > 0

                Text { text: "最近"; color: dimColor; font.pointSize: 8 }
                Repeater {
                    model: root.histList
                    delegate: QQC.Button {
                        text: modelData
                        font.pointSize: 8
                        onClicked: {
                            searchField.text = modelData;
                            root.doSearch(modelData);
                        }
                    }
                }
            }

            // ---- 标签栏（用 Flow，标签多了自动换行，不会撑宽面板）----
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.tabs

                    delegate: QQC.Button {
                        text: modelData.name
                        checkable: true
                        checked: root.activeView === "tabs" && root.activeTabIndex === index
                        onClicked: root.openTab(index)

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                root.ctxTabIndex = index;
                                ctxTabMenu.popup();
                            }
                        }
                    }
                }
                QQC.Button {
                    text: "收藏"
                    checkable: true
                    checked: root.activeView === "fav"
                    onClicked: root.openFav()
                }
                QQC.Button {
                    text: "搜索"
                    checkable: true
                    checked: root.activeView === "search"
                    onClicked: root.activeView = "search"
                }
                QQC.Button {
                    text: "+"
                    font.bold: true
                    implicitWidth: Math.round(Kirigami.Units.gridUnit * 2)
                    onClicked: root.showNewTab = !root.showNewTab
                }
            }

            // ---- 新建标签 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.showNewTab

                QQC.TextField {
                    id: newTabField
                    Layout.fillWidth: true
                    placeholderText: "新标签名，例如 古典 / 讲座"
                    onAccepted: {
                        root.createTab(newTabField.text);
                        newTabField.text = "";
                        root.showNewTab = false;
                    }
                }
                QQC.Button {
                    text: "创建"
                    onClicked: {
                        root.createTab(newTabField.text);
                        newTabField.text = "";
                        root.showNewTab = false;
                    }
                }
                QQC.Button {
                    text: "取消"
                    onClicked: root.showNewTab = false
                }
            }

            // ---- 选择目标标签 ----
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.pendingTabAction.length > 0

                Text {
                    text: root.pendingTabAction === "add" ? "添加到：" : "移到："
                    color: dimColor
                    font.pointSize: 8
                }
                Repeater {
                    model: root.tabs
                    delegate: QQC.Button {
                        text: modelData.name
                        font.pointSize: 8
                        onClicked: root.applyTabAction(modelData.name)
                    }
                }
                QQC.Button {
                    text: "取消"
                    font.pointSize: 8
                    onClicked: root.pendingTabAction = ""
                }
            }

            // ---- 播放状态行 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: player.playbackState === MediaPlayer.PlayingState
                            ? "media-playback-pause" : "media-playback-start"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                }
                Text {
                    Layout.fillWidth: true
                    text: root.nowPlaying.length > 0
                          ? (root.nowPlaying + " · " + root.statusText)
                          : root.statusText
                    color: root.errText.length > 0 ? warnColor : Kirigami.Theme.textColor
                    font.pointSize: 8
                    elide: Text.ElideRight
                }
                QQC.Button {
                    text: "播放/暂停"
                    enabled: player.source != ""
                    onClicked: root.togglePlay()
                }
                QQC.Button {
                    text: "停止"
                    enabled: player.source != ""
                    onClicked: {
                        player.stop();
                        root.nowPlaying = "";
                    }
                }
            }

            // ---- 频道列表 ----
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                rightMargin: Math.round(Kirigami.Units.gridUnit * 1.0)
                model: root.currentModel
                QQC.ScrollBar.vertical: QQC.ScrollBar { }

                // 不用 ItemDelegate：Control 自己会吃掉指针事件，
                // contentItem 里再放 MouseArea 收不到点击。用 Rectangle + MouseArea 最稳。
                delegate: Rectangle {
                    width: list.width - list.rightMargin
                    height: Math.round(Kirigami.Units.gridUnit * 2)
                    color: rowMouse.containsMouse
                           ? Qt.rgba(Kirigami.Theme.hoverColor.r, Kirigami.Theme.hoverColor.g,
                                     Kirigami.Theme.hoverColor.b, 0.25)
                           : "transparent"

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.ctxTarget = { "name": model.name, "url": model.url };
                                root.ctxTabIndex = root.activeTabIndex;
                                ctxMenu.popup();
                            } else {
                                root.playStation(model.name, model.url);
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Text {
                            Layout.fillWidth: true
                            text: (root.nowPlaying === model.name
                                   && player.playbackState === MediaPlayer.PlayingState)
                                  ? ("▶ " + model.name) : model.name
                            color: Kirigami.Theme.textColor
                            font.pointSize: 9
                            elide: Text.ElideRight
                        }
                        QQC.Button {
                            text: root.isFav(model.name, model.url) ? "★" : "☆"
                            flat: true
                            implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.8)
                            implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.6)
                            onClicked: root.toggleFav(model.name, model.url)
                        }
                    }
                }
            }

            Text {
                visible: list.count === 0
                text: root.activeView === "fav" ? "还没有收藏 —— 点频道右侧的 ☆"
                                               : (root.activeView === "search" ? "输入关键词，或用「筛选」按钮"
                                                                              : "这个标签还是空的 —— 在搜索结果里右键添加")
                color: dimColor
                font.pointSize: 8
                Layout.fillWidth: true
            }

            // ---- 音量 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillWidth: true }
                Text { text: "音量"; color: dimColor; font.pointSize: 8 }
                QQC.Slider {
                    id: volumeSlider
                    Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 8)
                    from: 0
                    to: 1
                    value: plasmoid.configuration.volume
                    Component.onCompleted: audioOut.volume = value
                    onValueChanged: audioOut.volume = value
                    onMoved: {
                        plasmoid.configuration.volume = value;
                        if (typeof plasmoid.configuration.writeConfig === "function")
                            plasmoid.configuration.writeConfig();
                    }
                }
            }

            Text {
                visible: root.errText.length > 0
                text: root.errText
                color: warnColor
                font.pointSize: 8
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // ---- 频道右键菜单 ----
        QQC.Menu {
            id: ctxMenu

            QQC.MenuItem {
                text: "添加到标签…"
                enabled: root.tabs.length > 0
                onTriggered: root.pendingTabAction = "add"
            }
            QQC.MenuItem {
                text: "从本标签移除"
                visible: root.activeView === "tabs"
                onTriggered: {
                    if (root.ctxTarget)
                        root.removeFromTab(root.activeTabIndex, root.ctxTarget.url);
                }
            }
            QQC.MenuItem {
                text: "移到标签…"
                visible: root.activeView === "tabs"
                enabled: root.tabs.length > 1
                onTriggered: root.pendingTabAction = "move"
            }
        }

        // ---- 标签右键菜单（删除标签）----
        QQC.Menu {
            id: ctxTabMenu

            QQC.MenuItem {
                text: "删除此标签"
                enabled: root.tabs.length > 1
                onTriggered: root.deleteTab(root.ctxTabIndex)
            }
        }
    }

    compactRepresentation: Item {
        id: compact
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 22)
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 2)
        // 面板的 applet 容器是 Layout，普通 Item 的 implicitWidth 不一定被采用，
        // 会被压到最小宽度（实测被压到 34px，台名只剩图标的位置）
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: Math.round(Kirigami.Units.gridUnit * 10)

        // Plasma 在鼠标按下时也会碰 expanded，记住按下前的状态再取反，避免抖动
        property bool wasExpanded: false

        Component.onCompleted: console.log("[radio] compact width " + width + "x" + height)
        onWidthChanged: console.log("[radio] compact resized -> " + width)
        onImplicitWidthChanged: console.log("[radio] compact implicitWidth -> " + implicitWidth)

        MouseArea {
            anchors.fill: parent
            onPressed: compact.wasExpanded = root.expanded
            onClicked: root.expanded = !compact.wasExpanded
        }

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small

                Kirigami.Icon {
                    anchors.fill: parent
                    source: player.playbackState === MediaPlayer.PlayingState
                            ? "media-playback-pause" : "media-playback-start"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.togglePlay()
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.nowPlaying.length > 0 ? root.nowPlaying : "电台"
                color: Kirigami.Theme.textColor
                font.pointSize: 9
                elide: Text.ElideRight
                // 宽度不够时自动缩小字号，尽量把台名完整显示出来
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: 7
            }

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: "arrow-down"
                opacity: 0.8
            }
        }
    }
}
