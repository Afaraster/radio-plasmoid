# 电台 · KDE Plasma 桌面组件

在 KDE Plasma 6 上听网络电台的极简组件：新闻 / 音乐 / 收藏三页预置频道，加一个搜索框和几个筛选按钮。

从零自建，不依赖 Hermes 桌面端，也不引入任何额外进程 —— 音频在 `plasmashell` 进程内由
QtMultimedia 播放，搜索是一次 `XMLHttpRequest`，全部代码就是一个 QML 文件。

## 功能（v0.2）

- **标签页**：新闻 / 音乐 / 收藏 / 搜索。每个标签默认只展开前 5 个台，超出部分用「展开全部」。
- **收藏**：每个频道右侧一个 ☆，点一下变 ★ 并收进「收藏」页；**重启后不丢**（存在组件配置里）。
- **搜索**：走 [Radio Browser](https://api.radio-browser.info/) 目录，按投票数排序取前 60 条，
  过滤 HLS、按 URL 去重。
- **筛选**：一排按钮 —— 中国（`countrycode=CN`）、新闻 / 音乐 / 钢琴 / 爵士（`tag=*`），
  可以和关键词组合，例如「中国」+「新闻」。只按筛选也能搜（不用输入关键词）。
- **清空**：搜索框右边的 ✕ 清空输入并回到原来的标签页。
- **最近搜索**：记住最近 6 个搜索词，点一下就重新搜；同样持久化。
- **播放**：点频道名开播，播放/暂停、停止、音量（音量也记住）。
- **回到预设**：清空搜索框后点「搜索」不再报错，会直接回到原来的标签页；点任意标签页也能回去。
- **记住上次停留的标签页**，下次打开还在那一页。

还没做的：曲目名（ICY 元数据）、波形、录播、投放、配置页。外观是原生的朴素样式。

## 依赖

| 项 | 要求 | 本机实测 |
| --- | --- | --- |
| 桌面 | KDE Plasma 6.x | 6.3.6 ✅ |
| QtMultimedia QML 模块 | `qml6-module-qtmultimedia` | 6.8.2-8 ✅ |
| 音频后端 | Qt 的 FFmpeg 后端（`libffmpegmediaplugin.so`） | 已随 `libqt6multimedia6` 装上 ✅ |

没有 Python、没有 systemd 单元、没有外部播放器。

## 安装

```bash
git clone https://github.com/Afaraster/radio-plasmoid.git
cd radio-plasmoid
./install.sh
```

然后右键桌面/面板 → 添加组件 → 搜索「电台」。若列表里还没出现，重启一次 shell：
`systemctl --user restart plasma-plasmashell`。

组件默认尺寸约 900×760；高度太小（例如 300px）会把里面的控件压扁到看不见。

## 预置频道（实测记录）

2026-10-17 在本机用 `mpv --ao=null --length=5` 逐个验证，均能解出音频轨。

**新闻**

| 台 | 编码 | 结果 |
| --- | --- | --- |
| CNR-1 中国之声 | MP3 48 kHz 64 kbps | ✅ |
| 上海新闻广播 | MP3 44.1 kHz 64 kbps（HTTP） | ✅ |
| 北京新闻广播 | MP3 48 kHz 64 kbps | ✅ |
| 广东新闻广播 | MP3 48 kHz 64 kbps | ✅ |
| 国际新闻 | MP3 44.1 kHz 64 kbps | ✅ |

**音乐（工作背景向）**

| 台 | 编码 | 结果 |
| --- | --- | --- |
| RadioArt 独奏钢琴 | MP3 44.1 kHz 96 kbps | ✅ |
| Epic Piano 钢琴氛围 | MP3 44.1 kHz 192 kbps | ✅ |
| Nightride Chillsynth | MP3 44.1 kHz 320 kbps | ✅ |
| Radio Paradise Main | AAC 44.1 kHz 129 kbps | ✅ |
| Radio Paradise Mellow | AAC 44.1 kHz 318 kbps | ✅ |
| Nightwave Plaza | AAC 44.1 kHz 70 kbps | ✅ |
| I Love Music · Chillhop | MP3 44.1 kHz 192 kbps | ✅ |
| WALM 2 古典 HD | MP3 48 kHz 237 kbps | ✅ |
| EVE Radio | MP3 44.1 kHz 256 kbps | ✅ |

搜索里能用的中文关键词（同一目录实测）：`新闻` → 27 个可播台；`中国之声`、`音乐`、`jazz`、
`house`、`classical`、`ambient` 都有结果。

## 持久化

收藏、搜索历史、音量、上次停留的标签页写在 `plasmoid.configuration` 里，落到
`~/.config/plasma-org.kde.plasma.desktop-appletsrc` 的
`[Containments][<n>][Applets][<id>][Configuration][General]` 组：

```
favorites=[{"name":"…","url":"…"}, …]
history=["jazz","新闻","piano"]
lastTab=fav
volume=0.8
```

字段在 `contents/config/main.xml` 里声明（KConfigXT）。实测：写入 6 条收藏 + 3 条历史并把
`lastTab` 设为 `fav`，重启 `plasma-plasmashell` 后组件日志读回完全一致。

## 缓存与资源占用（实测）

- **音频只在内存**：QtMultimedia 的 FFmpeg 后端把流缓冲在 plasmashell 进程内，换台 / 停止即释放，磁盘上不落音频。
- **播放时实测**：`ss -tnp` 只看到一条到广播方的直连 TCP，不经本地代理、不经任何中间缓存；`lsof -p $(pgrep -x plasmashell)` 里与本组件相关的只有 `.cache/plasmashell/qmlcache/*.qmlc`（QML 字节码缓存，与音频无关）。
- **网络层没有磁盘缓存**：Qt 的 `QNetworkDiskCache` 默认关闭，必须显式设置缓存目录才生效；本组件没有设置。
- **没有额外进程**：无 Python、无 systemd 单元、无第二个播放器进程。
- 每次换台那几秒的连接/缓冲是直播流固有的（服务端不提供可缓存内容，且每次都要重新握手 + 填抖动缓冲），不是缺缓存。

## 已知限制

- 搜索固定取前 60 条，没有翻页。
- 预置台的地址来自公开目录，会随时间失效；失效后在搜索里重新找即可。
- 搜索结果不受标签页折叠限制（默认同样只显示前 5 条，可展开）。

## 卸载

```bash
rm -rf ~/.local/share/plasma/plasmoids/io.github.afaraster.radio
```

## 许可

MIT。电台流由各广播方提供，本项目只做地址解析与播放，不录制、不转发。
