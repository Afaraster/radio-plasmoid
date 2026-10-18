#!/usr/bin/env bash
# 安装 / 升级电台 Plasma 组件。只写 $HOME 下的文件，不需要 root。
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.afaraster.radio"
BIN_DIR="$HOME/.local/bin"

echo "==> 安装输出设备纠正脚本到 $BIN_DIR/radio-follow-default"
install -Dm755 "$SRC/bin/radio-follow-default" "$BIN_DIR/radio-follow-default"

echo "==> 安装 Plasma 组件 $PLUGIN_ID"
if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$SRC/plasmoid/$PLUGIN_ID" >/dev/null 2>&1 \
        || kpackagetool6 --type Plasma/Applet --install "$SRC/plasmoid/$PLUGIN_ID"
else
    echo "!! 没找到 kpackagetool6，直接拷贝到 ~/.local/share/plasma/plasmoids"
    mkdir -p "$HOME/.local/share/plasma/plasmoids"
    cp -r "$SRC/plasmoid/$PLUGIN_ID" "$HOME/.local/share/plasma/plasmoids/"
fi

cat <<'EOF'

下一步：
  1. 添加组件 —— 右键桌面/面板 → 添加组件 → 搜索 “电台”
  2. 若列表里还没出现，重启一次 shell：systemctl --user restart plasma-plasmashell
  3. 改了 QML 之后重跑本脚本即可热升级；若界面没变，把组件删掉再加一次

卸载：
  rm -rf ~/.local/share/plasma/plasmoids/io.github.afaraster.radio
  rm -f  ~/.local/bin/radio-follow-default
EOF
