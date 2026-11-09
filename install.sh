#!/usr/bin/env bash
# 安装/卸载每周巡检。用法：./install.sh  或  ./install.sh uninstall
set -eu
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL=com.markwave.disk-guard
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = uninstall ]; then
  rm -f "$DEST"; [ -L "$HOME/.disk-guard" ] && rm "$HOME/.disk-guard"; echo "已卸载 $LABEL（reports/ 保留）"; exit 0
fi
mkdir -p "$KIT_DIR/logs" "$KIT_DIR/reports" "$HOME/Library/LaunchAgents"
ln -sfn "$KIT_DIR" "$HOME/.disk-guard"
chmod +x "$KIT_DIR/scripts/"*.sh
sed "s#__KIT_DIR__#$KIT_DIR#g" "$KIT_DIR/launchd/$LABEL.plist" >"$DEST"
plutil -lint "$DEST"
launchctl bootstrap "gui/$(id -u)" "$DEST"
launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|path' | head -3
echo "已安装：每周一 09:30 运行 scan.sh。立即试跑：launchctl kickstart gui/$(id -u)/$LABEL"
DISK_GUARD_NOTIFY=0 "$KIT_DIR/scripts/scan.sh" >/dev/null && echo "基线报告：$HOME/.disk-guard/reports/latest.md"
