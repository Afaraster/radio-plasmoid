// 极简电台挂件 —— 预置频道 + Radio Browser 关键词搜索。
// 播放走 QtMultimedia（Debian 的 Qt 6.8 用的是 FFmpeg 后端，见
// /usr/lib/x86_64-linux-gnu/qt6/plugins/multimedia/libffmpegmediaplugin.so），
// 不额外起进程；搜索是一次 XMLHttpRequest，不引入任何依赖。
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

    property string statusText: "未播放"
    property string errText: ""
    property string nowPlaying: ""
    property bool searching: false
    property var _xhr: null

    preferredRepresentation: fullRepresentation

    // 预置台。URL 于 2026-10-17 在本机用 mpv 逐个实测解出音频轨（MP3/AAC）。
    ListModel {
        id: stations

        ListElement { name: "CNR-1 中国之声"; url: "https://lhttp.qtfm.cn/live/15318317/64k.mp3"; preset: true }
        ListElement { name: "上海新闻广播"; url: "http://lhttp.qingting.fm/live/270/64k.mp3"; preset: true }
        ListElement { name: "北京新闻广播"; url: "https://lhttp.qtfm.cn/live/339/64k.mp3"; preset: true }
        ListElement { name: "广东新闻广播"; url: "https://lhttp.qtfm.cn/live/1254/64k.mp3"; preset: true }
        ListElement { name: "国际新闻"; url: "https://lhttp.qtfm.cn/live/20500172/64k.mp3"; preset: true }
        ListElement { name: "Nightride Chillsynth"; url: "https://stream.nightride.fm/chillsynth.mp3"; preset: true }
        ListElement { name: "Radio Paradise Main"; url: "https://stream.radioparadise.com/aac-128"; preset: true }
        ListElement { name: "EVE Radio"; url: "https://eve.gamingnow.net:8010/erweb.mp3"; preset: true }
    }

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

    // 注意：fullRepresentation 的类型是 Component，它内部的 id（searchField）在 root 这层
    // 不可见 —— 所以输入框的文本必须由调用方传进来，不能在这里直接读 searchField。
    function doSearch(text) {
        text = String(text || "").trim();
        if (text.length === 0) {
            root.errText = "请输入关键词，例如 新闻 / jazz / house";
            return;
        }
        if (root.searching)
            return;
        root.searching = true;
        root.errText = "";
        root.statusText = "正在搜索「" + text + "」…";

        var xhr = root._xhr = new XMLHttpRequest();   // 挂到 root 上，避免请求飞行中被回收
        var url = root.directoryApi + "?name=" + encodeURIComponent(text)
                + "&limit=60&hidebroken=true&order=votes&reverse=true";
        xhr.open("GET", url);
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
            stations.clear();
            var seen = [];
            var n = 0;
            for (var i = 0; i < rows.length; i++) {
                var row = rows[i];
                var u = row.url_resolved || "";
                // 与 Hermes 插件同一套过滤：必须有 HTTPS 或 HTTP 可直接拉取的流，排除 HLS
                if (!u || row.hls === true || !row.stationuuid || !row.name)
                    continue;
                if (seen.indexOf(u) !== -1)
                    continue;
                seen.push(u);
                stations.append({
                    "name": String(row.name).trim(),
                    "url": u,
                    "preset": false
                });
                n++;
            }
            root.statusText = n > 0 ? ("找到 " + n + " 个电台") : "没有找到电台";
        };
        xhr.send();
    }

    toolTipMainText: "电台"
    toolTipSubText: root.nowPlaying.length > 0
                    ? (root.nowPlaying + "\n" + root.statusText)
                    : root.statusText

    fullRepresentation: Item {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 21)
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 24)

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

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
            }

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

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: stations

                delegate: QQC.ItemDelegate {
                    width: list.width
                    text: model.name + (model.preset ? "    预设" : "")

                    onClicked: root.playStation(model.name, model.url)

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: (root.nowPlaying === model.name
                                     && player.playbackState === MediaPlayer.PlayingState)
                                    ? "media-playback-start" : ""
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth

                            // 装饰性图标，没在播就整块消失，不占空间
                            Layout.preferredWidth: source.toString().length > 0
                                                   ? Kirigami.Units.iconSizes.small : 0
                        }
                        Text {
                            Layout.fillWidth: true
                            text: model.name
                            color: Kirigami.Theme.textColor
                            font.pointSize: 9
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: model.preset
                            text: "预设"
                            color: dimColor
                            font.pointSize: 7
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: "音量"
                    color: dimColor
                    font.pointSize: 8
                }
                QQC.Slider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: 0.8
                    onValueChanged: audioOut.volume = value
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
