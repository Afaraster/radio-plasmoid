# 电台 · KDE Plasma 桌面组件

在 KDE Plasma 6 上听网络电台的极简组件：一组预置频道 + 一个搜索框，点一下开播。

这是从零自建的组件，不依赖 Hermes 桌面端，也不引入任何额外进程 —— 音频在 `plasmashell`
进程内由 QtMultimedia 播放，搜索是一次 `XMLHttpRequest`。

## 现状（v0.1，最小可用）

- **预置频道**：8 个写死在 QML 里的台，URL 已逐个实测可播（见下表）。
- **关键词搜索**：走 [Radio Browser](https://api.radio-browser.info/) 目录，按投票数排序，
  取前 60 条；过滤掉 HLS 流并按 URL 去重。
- **播放控制**：播放/暂停、停止、音量。
- **紧凑形态**：放在面板上时显示一个图标 + 当前台名。

还没做的：收藏/置顶、曲目名（ICY 元数据）、波形、录播、投放。外观是原生的朴素样式。

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

## 预置频道（实测记录）

2026-10-17 在本机用 `mpv --ao=null --length=5` 逐个验证，均能解出音频轨：

| 台 | 编码 | 结果 |
| --- | --- | --- |
| CNR-1 中国之声 | MP3 48 kHz 64 kbps | ✅ |
| 上海新闻广播 | MP3 44.1 kHz 64 kbps（HTTP） | ✅ |
| 北京新闻广播 | MP3 48 kHz 64 kbps | ✅ |
| 广东新闻广播 | MP3 48 kHz 64 kbps | ✅ |
| 国际新闻 | MP3 44.1 kHz 64 kbps | ✅ |
| Nightride Chillsynth | MP3 44.1 kHz 320 kbps | ✅（含 ICY 曲目名） |
| Radio Paradise Main | AAC 44.1 kHz 129 kbps | ✅（含 ICY 曲目名） |
| EVE Radio | MP3 44.1 kHz 256 kbps | ✅（含 ICY 曲目名） |

搜索里能用的中文关键词举例（同一目录实测）：`新闻` → 27 个可播台；`中国之声`、`音乐`、
`jazz`、`house`、`classical`、`ambient` 都有结果。

## 卸载

```bash
rm -rf ~/.local/share/plasma/plasmoids/io.github.afaraster.radio
```

## 许可

MIT。电台流由各广播方提供，本项目只做地址解析与播放，不录制、不转发。
