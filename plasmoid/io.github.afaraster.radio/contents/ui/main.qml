// 极简电台挂件 —— 标签页（新闻 / 音乐 / 收藏 / 搜索）+ 关键词与筛选搜索。
// 播放走 QtMultimedia（Debian 的 Qt 6.8 用 FFmpeg 后端），搜索是一次 XMLHttpRequest。
// 收藏、搜索历史、音量、上次停留的标签页存在 plasmoid.configuration 里（contents/config/main.xml）。
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtMultimedia
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color dimColor: Kirigami.Theme.disabledTextColor
    readonly property color warnColor: Kirigami.Theme.negativeTextColor
    readonly property string directoryApi: "https://de1.api.radio-browser.info/json/stations/search"
    readonly property int collapsedCount: 5
    readonly property int historyLimit: 6
    readonly property int searchLimit: 60

    // ---- 持久化状态 ----
    property var favList: []
    property var histList: []
    property string activeTab: "news"
    property string returnTab: "news"

    // ---- 搜索筛选（"" = 不筛）----
    property string countryFilter: ""
    property string tagFilter: ""

    // ---- 界面状态 ----
    property bool expanded: false
    property string statusText: "未播放"
    property string errText: ""
    property string nowPlaying: ""
    property bool searching: false
    property var _xhr: null

    preferredRepresentation: fullRepresentation

    // 预置台。URL 于 2026-10-17 在本机用 mpv 逐个实测解出音频轨（MP3/AAC）。
    ListModel {
        id: newsModel

        ListElement { name: "CNR-1 中国之声"; url: "https://lhttp.qtfm.cn/live/15318317/64k.mp3" }
        ListElement { name: "上海新闻广播"; url: "http://lhttp.qingting.fm/live/270/64k.mp3" }
        ListElement { name: "北京新闻广播"; url: "https://lhttp.qtfm.cn/live/339/64k.mp3" }
        ListElement { name: "广东新闻广播"; url: "https://lhttp.qtfm.cn/live/1254/64k.mp3" }
        ListElement { name: "国际新闻"; url: "https://lhttp.qtfm.cn/live/20500172/64k.mp3" }
    }

    ListModel {
        id: musicModel

        ListElement { name: "RadioArt 独奏钢琴"; url: "http://live.radioart.com/fSolo_piano.mp3" }
        ListElement { name: "Epic Piano 钢琴氛围"; url: "https://stream.epic-piano.com/chillout-piano?ref=radiobrowser" }
        ListElement { name: "Nightride Chillsynth"; url: "https://stream.nightride.fm/chillsynth.mp3" }
        ListElement { name: "Radio Paradise Main"; url: "https://stream.radioparadise.com/aac-128" }
        ListElement { name: "Radio Paradise Mellow"; url: "https://stream.radioparadise.com/mellow-320" }
        ListElement { name: "Nightwave Plaza"; url: "http://radio.plaza.one/opus" }
        ListElement { name: "I Love Music · Chillhop"; url: "https://ilm.stream12.radiohost.de/ilm_ilovechillhop_mp3-192?upd-meta&upd-scheme=https" }
        ListElement { name: "WALM 2 古典 HD"; url: "https://icecast.walmradio.com:8443/walm2" }
        ListElement { name: "EVE Radio"; url: "https://eve.gamingnow.net:8010/erweb.mp3" }
    }

    ListModel {
        id: favModel
    }

    ListModel {
        id: searchModel
    }

    property var currentModel: activeTab === "music" ? musicModel
                             : activeTab === "fav" ? favModel
                             : activeTab === "search" ? searchModel
                             : newsModel

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audioOut
            volume: 0.8
        }

        onPlaybackStateChanged: function (state) {
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

    // ---------- 配置读写 ----------

    function persist() {
        plasmoid.configuration.favorites = JSON.stringify(root.favList);
        plasmoid.configuration.history = JSON.stringify(root.histList);
        plasmoid.configuration.lastTab = root.activeTab;
        if (typeof plasmoid.configuration.writeConfig === "function")
            plasmoid.configuration.writeConfig();
    }

    function loadConfig() {
        try {
            root.favList = JSON.parse(plasmoid.configuration.favorites || "[]") || [];
        } catch (e) {
            root.favList = [];
        }
        try {
            root.histList = JSON.parse(plasmoid.configuration.history || "[]") || [];
        } catch (e) {
            root.histList = [];
        }
        root.rebuildFavModel();
        var t = plasmoid.configuration.lastTab;
        root.activeTab = (t === "music" || t === "fav") ? t : "news";
        root.returnTab = root.activeTab;
        console.log("[radio] loaded favorites=" + JSON.stringify(root.favList)
                    + " history=" + JSON.stringify(root.histList)
                    + " tab=" + root.activeTab);
    }

    Component.onCompleted: root.loadConfig()

    // ---------- 收藏 ----------

    function isFav(name, url) {
        for (var i = 0; i < root.favList.length; i++) {
            if (root.favList[i].url === url)
                return true;
        }
        return false;
    }

    function rebuildFavModel() {
        favModel.clear();
        for (var i = 0; i < root.favList.length; i++) {
            favModel.append({
                "name": root.favList[i].name,
                "url": root.favList[i].url
            });
        }
    }

    function toggleFav(name, url) {
        var next = [];
        var found = false;
        for (var i = 0; i < root.favList.length; i++) {
            if (root.favList[i].url === url) {
                found = true;
                continue;
            }
            next.push(root.favList[i]);
        }
        if (!found)
            next.push({ "name": name, "url": url });
        root.favList = next;
        root.rebuildFavModel();
        root.persist();
        console.log("[radio] favorites now " + JSON.stringify(root.favList));
    }

    // ---------- 播放 ----------

    function playStation(name, url) {
        root.errText = "";
        root.nowPlaying = name;
        player.stop();
        player.source = url;
        player.play();
    }

    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else if (player.source != "")
            player.play();
    }

    // ---------- 标签页 ----------

    function showTab(id) {
        if (id !== "search")
            root.returnTab = id;
        root.activeTab = id;
        root.expanded = false;
        root.errText = "";
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
        for (var i = 0; i < root.histList.length && next.length < root.historyLimit; i++) {
            if (root.histList[i] !== text)
                next.push(root.histList[i]);
        }
        root.histList = next;
        root.persist();
    }

    function clearSearch() {
        searchField.text = "";
        root.countryFilter = "";
        root.tagFilter = "";
        root.errText = "";
        root.showTab(root.returnTab === "search" ? "news" : root.returnTab);
    }

    function doSearch(text) {
        text = String(text || "").trim();
        if (text.length === 0 && root.countryFilter.length === 0 && root.tagFilter.length === 0) {
            // 空搜索 = 回到预设，不再报错
            root.showTab(root.returnTab === "search" ? "news" : root.returnTab);
            return;
        }
        if (root.searching)
            return;
        if (root.activeTab !== "search")
            root.returnTab = root.activeTab;
        root.searching = true;
        root.errText = "";
        root.statusText = "正在搜索…";

        var xhr = root._xhr = new XMLHttpRequest();   // 挂到 root 上，避免请求飞行中被回收
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
            try {
                rows = JSON.parse(xhr.responseText);
            } catch (e) {
                root.errText = "结果解析失败：" + e;
                root.statusText = "搜索失败";
                return;
            }
            searchModel.clear();
            var seen = [];
            var n = 0;
            for (var i = 0; i < rows.length; i++) {
                var row = rows[i];
                var u = row.url_resolved || "";
                // 只留可直接拉取的流（HTTP/HTTPS），排除 HLS，并按 URL 去重
                if (!u || row.hls === true || !row.stationuuid || !row.name)
                    continue;
                if (seen.indexOf(u) !== -1)
                    continue;
                seen.push(u);
                searchModel.append({
                    "name": String(row.name).trim(),
                    "url": u
                });
                n++;
            }
            root.activeTab = "search";
            root.expanded = false;
            root.rememberQuery(text);
            root.statusText = n > 0 ? ("找到 " + n + " 个电台") : "没有找到电台";
        };
        xhr.send();
    }

    toolTipMainText: "电台"
    toolTipSubText: root.nowPlaying.length > 0 ? (root.nowPlaying + "\n" + root.statusText) : root.statusText

    fullRepresentation: Item {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 24)
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 33)

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            radius: Math.round(Kirigami.Units.smallSpacing)
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor
        }

        ColumnLayout {
            id: col
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
                    onClicked: root.clearSearch()
                }
            }

            // ---- 筛选行 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: "筛选"
                    color: dimColor
                    font.pointSize: 8
                }
                QQC.Button {
                    text: "中国"
                    checkable: true
                    checked: root.countryFilter === "CN"
                    font.pointSize: 8
                    onClicked: root.countryFilter = (root.countryFilter === "CN" ? "" : "CN")
                }
                QQC.Button {
                    text: "新闻"
                    checkable: true
                    checked: root.tagFilter === "news"
                    font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "news" ? "" : "news")
                }
                QQC.Button {
                    text: "音乐"
                    checkable: true
                    checked: root.tagFilter === "music"
                    font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "music" ? "" : "music")
                }
                QQC.Button {
                    text: "钢琴"
                    checkable: true
                    checked: root.tagFilter === "piano"
                    font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "piano" ? "" : "piano")
                }
                QQC.Button {
                    text: "爵士"
                    checkable: true
                    checked: root.tagFilter === "jazz"
                    font.pointSize: 8
                    onClicked: root.tagFilter = (root.tagFilter === "jazz" ? "" : "jazz")
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // ---- 搜索历史 ----
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.histList.length > 0

                Text {
                    text: "最近"
                    color: dimColor
                    font.pointSize: 8
                }
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

            // ---- 标签页 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC.Button {
                    text: "新闻"
                    checkable: true
                    checked: root.activeTab === "news"
                    onClicked: root.showTab("news")
                }
                QQC.Button {
                    text: "音乐"
                    checkable: true
                    checked: root.activeTab === "music"
                    onClicked: root.showTab("music")
                }
                QQC.Button {
                    text: "收藏"
                    checkable: true
                    checked: root.activeTab === "fav"
                    onClicked: root.showTab("fav")
                }
                QQC.Button {
                    text: "搜索"
                    checkable: true
                    checked: root.activeTab === "search"
                    onClicked: root.showTab("search")
                }
                Item {
                    Layout.fillWidth: true
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

            // ---- 台列表 ----
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.currentModel

                delegate: QQC.ItemDelegate {
                    width: list.width
                    visible: root.expanded || index < root.collapsedCount
                    height: visible ? implicitHeight : 0

                    onClicked: root.playStation(model.name, model.url)

                    contentItem: RowLayout {
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
                text: root.activeTab === "fav" ? "还没有收藏 —— 点频道右侧的 ☆ 收藏"
                                               : (root.activeTab === "search" ? "在上面的搜索框输入关键词，或用「筛选」按钮"
                                                                              : "没有频道")
                color: dimColor
                font.pointSize: 8
                Layout.fillWidth: true
            }

            // ---- 展开 / 音量 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC.Button {
                    visible: list.count > root.collapsedCount
                    text: root.expanded ? "收起" : ("展开全部（" + list.count + "）")
                    font.pointSize: 8
                    onClicked: root.expanded = !root.expanded
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: "音量"
                    color: dimColor
                    font.pointSize: 8
                }
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
    }

    compactRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "applications-multimedia"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }
        Text {
            text: root.nowPlaying.length > 0 ? root.nowPlaying : "电台"
            color: Kirigami.Theme.textColor
            font.pointSize: 9
        }
    }
}
