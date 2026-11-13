# 电台 · KDE Plasma 桌面组件

在 KDE Plasma 6 上听网络电台和网易云音乐：可编辑的标签页 + 一个共用搜索框。

![截图](assets/screenshot.png)

电台仍由 QtMultimedia 在 `plasmashell` 内播放，目录搜索走 Radio Browser。
网易云歌曲由官方 `@music163/ncm-cli` 搜索并通过 mpv 播放，挂件统一控制播放、暂停、停止和音量。
`bin/radio-ncm` 是按需运行的 Python JSON 桥接脚本，没有额外的 HTTP 服务或 systemd 单元。

## 功能

- **两个形态**：放在面板上是紧凑态（播放/暂停图标 + 台名 + 下拉箭头），点开是完整面板；放在桌面上直接是完整面板。
- **可编辑标签页**：默认「新闻」「音乐」两页，可自己新建、删除；频道可以跨标签移动。
- **收藏**：每个频道右侧一个 ☆，点一下变 ★ 并收进「收藏」页，和标签互不影响（同一个台可以既在标签里也收藏）。
- **右键菜单**：搜索结果里右键 → 「添加到标签…」；标签页里右键 → 「从本标签移除」「移到标签…」；右键标签按钮 → 「删除此标签」。
- **共用搜索框**：左侧选择「网易云」可按歌曲名或歌手搜索；选择「电台」保留原来的目录搜索。歌曲可使用现有收藏与标签功能，和电台混合保存。
- **电台搜索**：走 [Radio Browser](https://api.radio-browser.info/) 目录，按投票数排序取前 60 条，过滤 HLS、按 URL 去重。
- **筛选**：中国（`countrycode=CN`）、新闻 / 音乐 / 钢琴 / 爵士（`tag=*`），可与关键词组合，也能只按筛选搜。
- **最近搜索**：记住最近 6 个搜索词与来源，点一下自动切换来源并重新搜索。
- **清空**：搜索框右边的 ✕，清空输入并回到原来的标签页。
- **记住上次播放的频道**：重启后点紧凑态的播放键就直接续播，不用先打开面板选台。
- 收藏、标签内容、搜索历史、音量、上次频道、上次停留的标签页全部持久化。

网易云搜索只展示当前账号可播放的结果，并提示被过滤的数量；版权、会员和地区权限由官方服务决定。

还没做的：歌曲自动连播 / 歌单队列、歌词、进度拖动、电台曲目名（ICY 元数据）、录播、投放、图形化配置页。

## 依赖

| 项 | 要求 | 本机实测 |
| --- | --- | --- |
| 桌面 | KDE Plasma 6.x | 6.3.6 ✅ |
| QtMultimedia QML 模块 | `qml6-module-qtmultimedia` | 6.8.2-8 ✅ |
| 音频后端 | Qt 的 FFmpeg 后端（`libffmpegmediaplugin.so`） | 已随 `libqt6multimedia6` 装上 ✅ |
| 网易云搜索 / 播放 | Node.js ≥18、`@music163/ncm-cli`、Python 3、mpv | CLI 0.1.7 / 本机已安装 ✅ |
| `pactl` | PulseAudio 自带，用于输出设备纠正脚本 | 已随 `pulseaudio-utils` 装上 ✅ |

## 安装

```bash
git clone https://github.com/Afaraster/radio-plasmoid.git
cd radio-plasmoid
./install.sh
```

`install.sh` 安装 `~/.local/bin/radio-follow-default`、`~/.local/bin/radio-ncm` 和 Plasma 组件本体。升级保留现有组件实例的收藏与标签。
然后右键桌面/面板 → 添加组件 → 搜索「电台」。若列表里还没出现，重启一次 shell：
`systemctl --user restart plasma-plasmashell`。

组件默认尺寸约 540×560；放在桌面上时高度太小（例如 300px）会把里面的控件压扁到看不见。

## 网易云配置与使用

```bash
npm install -g @music163/ncm-cli
ncm-cli configure
ncm-cli login
ncm-cli login --check
```

在[官网安装页](https://music.163.com/st/ncmcli#setup)登录获取自己的 appId / privateKey，
在 `configure` 向导中填写并选择 **mpv**。再用手机网易云音乐扫描 `login` 的二维码授权。
凭证由官方 CLI 保存在用户配置目录，挂件不读取私钥，不把凭证写入 Plasma 配置或仓库。

挂件搜索框左侧选「网易云」，输入歌曲名或歌手并回车，点结果播放。右侧 ☆ 可收藏，
右键可加入现有标签。「播放/暂停」「停止」和音量条同时支持电台与歌曲。
点击电台会先停止网易云播放器，点击歌曲会停止当前电台；不会自动播放下一首。

歌曲以 `ncm://<加密ID>/<原始ID>` 保存到原有收藏与标签，播放交给官方 CLI 重新取资源，
不会保存临时播放地址。`radio-ncm` 只把规范化结果和错误返回 QML，不把 CLI 原始诊断写入挂件日志。
CLI 0.1.7 的状态查询会把暂停的 mpv 报为停止，因此状态优先读取其本地 `mpv.sock`，不可用时回退 CLI。

故障检查：

```bash
ncm-cli --version
ncm-cli login --check
ncm-cli search song --keyword "xxx" --userInput "搜索xxx的歌" --output json
~/.local/bin/radio-ncm search "xxx"
```

提示 API key 未设置时重新运行 `ncm-cli configure`；授权过期时运行 `ncm-cli login`。
若升级后界面仍旧，保存其他桌面操作后运行 `systemctl --user restart plasma-plasmashell`。
独立预览可用 `plasmawindowed io.github.afaraster.radio`；每个实例的收藏仍然独立，网易云播放服务由当前账号共享。
不要同时在多个实例或 CLI TUI 中控制不同歌曲。

验证桥接回归检查：`python3 -m unittest discover -s tests -v`。

## 输出设备跟随（为什么需要一个脚本）

期望的行为是「像浏览器那样跟着系统默认输出走」：没插耳机走内置扬声器，插上耳机自动切过去。这件事需要两层才可靠：

1. **组件侧不指定设备**：`AudioOutput` 不写 `device`，Qt 在每次 `start()` 时取当时的系统默认输出。
2. **`bin/radio-follow-default` 兜底**：组件在每次开始播放约 1.5 秒后调用它一次，把 plasmashell 自己的音频流拨到 `pactl get-default-sink` 报出的那台设备。

为什么第 2 层是必要的：Qt 会在组件初始化时记住当时的默认输出设备，而开机时 `plasmashell` 通常比蓝牙耳机连上得早 —— Qt 记下的是内置声卡，之后创建音频流时会**显式指定**那台设备，于是系统默认明明是耳机、电台却没声音（手动在音量控件里切一下才恢复）。PulseAudio 的 `module-stream-restore` 只记忆「应用自己选过的设备」，管不住这种应用显式指定的情况。

脚本是幂等的：流已经在目标设备上时，`pactl move-sink-input` 是无副作用的空操作；找不到 plasmashell 的流或取不到默认设备时静默退出。

系统侧还有一组可选的 PulseAudio 改动（不属于本仓库，但不做的话「耳机接入时自动迁移正在播放的流」不生效）：

```
# ~/.config/pulse/default.pa
.include /etc/pulse/default.pa
unload-module module-stream-restore
load-module module-stream-restore restore_device=false
load-module module-switch-on-connect
```

删掉这个文件再 `systemctl --user restart pulseaudio` 即回滚。

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

搜索里能用的中文关键词（同一目录实测）：`新闻` → 27 个可播台；`中国之声`、`音乐`、`jazz`、`house`、`classical`、`ambient` 都有结果。

## 持久化

收藏、标签内容、搜索历史、音量、上次播放的频道、上次停留的视图写在 `plasmoid.configuration` 里，
落到 `~/.config/plasma-org.kde.plasma.desktop-appletsrc` 的
`[Containments][<n>][Applets][<id>][Configuration][General]` 组：

```
favorites=[{"name":"…","url":"…"}, …]
tabs=[{"name":"新闻","stations":[…]},{"name":"音乐","stations":[…]}]
history=["jazz","新闻","piano"]
lastStation={"name":"…","url":"…"}
lastTab=tabs:0
volume=0.8
```

字段在 `contents/config/main.xml` 里声明（KConfigXT）。实测：写入 6 条收藏 + 3 条历史并把
`lastTab` 设为 `fav`，重启 `plasma-plasmashell` 后组件日志读回完全一致。

注意：配置是**按组件实例**存的 —— 面板上一个、桌面上一个会各自拥有一份独立的收藏与标签。

## 电台缓存与资源占用（原有实测）

- **音频只在内存**：QtMultimedia 的 FFmpeg 后端把流缓冲在 plasmashell 进程内，换台 / 停止即释放，磁盘上不落音频。
- **播放时实测**：`ss -tnp` 只看到一条到广播方的直连 TCP，不经本地代理、不经任何中间缓存；`lsof -p $(pgrep -x plasmashell)` 里与本组件相关的只有 `.cache/plasmashell/qmlcache/*.qmlc`（QML 字节码缓存，与音频无关）。
- **网络层没有磁盘缓存**：Qt 的 `QNetworkDiskCache` 默认关闭，必须显式设置缓存目录才生效；本组件没有设置。
- **电台路径**：无常驻 Python、无 systemd 单元、无第二个播放器进程。网易云路径会按需运行桥接脚本和官方 CLI，并使用其播放服务与 mpv；缓存策略由官方 CLI 管理。
- 每次换台那几秒的连接/缓冲是直播流固有的（服务端不提供可缓存内容，且每次都要重新握手 + 填抖动缓冲），不是缺缓存。

## 已知限制

- 搜索固定取前 60 条，没有翻页；网易云在这批结果中过滤不可播放歌曲。
- 预置台的地址来自公开目录，会随时间失效；失效后在搜索里重新找即可。
- 输出设备跟随需要 `~/.local/bin/radio-follow-default` 存在（`install.sh` 会装）；删掉它之后，开机时若蓝牙比 plasmashell 连得晚，声音会落在内置声卡上。
- 「取下耳机自动暂停」未实现：TWS 耳机发的是 AVRCP 暂停指令，需要播放器注册 MPRIS 才能收到。

## 卸载

```bash
rm -rf ~/.local/share/plasma/plasmoids/io.github.afaraster.radio
rm -f  ~/.local/bin/radio-follow-default ~/.local/bin/radio-ncm
```

## 许可

MIT。电台流由各广播方提供，网易云歌曲通过官方 CLI 获取并播放；不录制、不转发。
