#!/usr/bin/env bash
# disk-guard 只读巡检：只测量、只写 reports/，从不删除、移动或修改任何其他文件。
set -u
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$KIT_DIR/config/paths.conf"
REPORT_DIR="$KIT_DIR/reports"
mkdir -p "$REPORT_DIR"
DATE="$(date +%Y-%m-%d)"
TS="$(date '+%Y-%m-%d %H:%M %Z')"
OUT_MD="$REPORT_DIR/$DATE.md"
OUT_TSV="$REPORT_DIR/$DATE.tsv"
PREV_TSV="$(ls -1 "$REPORT_DIR"/*.tsv 2>/dev/null | grep -v "/$DATE.tsv$" | sort | tail -1 || true)"
WARN_AVAIL_GB="${DISK_GUARD_WARN_AVAIL_GB:-50}"
WARN_USED_PCT="${DISK_GUARD_WARN_USED_PCT:-85}"
PROJECT_ROOT="${DISK_GUARD_PROJECT_ROOT:-$HOME/Cursor}"

gb() { awk -v k="${1:-0}" 'BEGIN{printf "%.1fG", k/1048576}'; }
size_k() { du -sk "$1" 2>/dev/null | tail -1 | awk '{print $1}'; }
prev_k() { [ -n "$PREV_TSV" ] && awk -F'\t' -v p="$1" '$1==p{print $2}' "$PREV_TSV"; }
delta() {
  local now="$1" before
  before="$(prev_k "$2")"
  [ -z "$before" ] && { echo "—"; return; }
  awk -v a="$now" -v b="$before" 'BEGIN{d=(a-b)/1048576; if (d>=0) printf "+%.1fG", d; else printf "%.1fG", d}'
}

if [ "$(uname)" = Darwin ] && [ -d /System/Volumes/Data ]; then VOL=/System/Volumes/Data; else VOL=/; fi
read -r SIZE_K USED_K AVAIL_K PCT <<<"$(df -k "$VOL" | awk 'NR==2{gsub("%","",$5); print $2,$3,$4,$5}')"
AVAIL_GB=$((AVAIL_K / 1048576))

: >"$OUT_TSV"
printf '__avail__\t%s\n' "$AVAIL_K" >>"$OUT_TSV"
ROWS=""
N=0
add_row() { # tier path kb label how
  N=$((N + 1))
  local kb="$3" shown d
  if [ -z "$kb" ]; then shown="无权限/不存在"; d="—"; else shown="$(gb "$kb")"; d="$(delta "$kb" "$2")"; printf '%s\t%s\n' "$2" "$kb" >>"$OUT_TSV"; fi
  ROWS+="| $N | $1 | \`$2\` | $shown | $d | $4 | $5 |"$'\n'
}

SNAP_NOTE=""
while IFS='|' read -r tier path label how; do
  case "$tier" in ''|\#*) continue ;; esac
  if [ "${tier#@}" != "$tier" ]; then how="$label"; label="$path"; path="$tier"; tier="X"; fi
  case "$path" in
    @node_modules|@venv)
      name=node_modules; [ "$path" = @venv ] && name=.venv
      list="$(find "$PROJECT_ROOT" -maxdepth 4 -type d -name "$name" -prune 2>/dev/null)"
      cnt=0; kb=0
      if [ -n "$list" ]; then
        cnt="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
        kb="$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{s+=$1} END{print s+0}')"
      fi
      add_row "$tier" "$PROJECT_ROOT/**/$name" "$kb" "${label}（${cnt} 个）" "$how" ;;
    @docker)
      f="$(find "$HOME/Library/Containers/com.docker.docker" -name Docker.raw 2>/dev/null | head -1)"
      if [ -n "$f" ]; then
        app="$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f")"
        add_row "$tier" "$f" "$(size_k "$f")" "${label}：显示 $(awk -v b="$app" 'BEGIN{printf "%.0fG", b/1073741824}')" "$how"
      fi ;;
    @snapshots)
      if command -v tmutil >/dev/null; then
        s="$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple' || true)"
        u="$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.os.update' || true)"
        SNAP_NOTE="APFS 本地快照 $s 个，其中系统更新快照 $u 个（${how}）。"
      fi ;;
    *)
      p="${path/#\~/$HOME}"
      [ -e "$p" ] && add_row "$tier" "$p" "$(size_k "$p")" "$label" "$how" ;;
  esac
done <"$CONF"

AVAIL_DELTA="$(delta "$AVAIL_K" "__avail__")"
ALERT=""
if [ "$AVAIL_GB" -lt "$WARN_AVAIL_GB" ] || [ "$PCT" -ge "$WARN_USED_PCT" ]; then
  ALERT="⚠️ 已越过阈值（可用 < ${WARN_AVAIL_GB}G 或占用 ≥ ${WARN_USED_PCT}%），建议本周跑一次 prompts/01-只读审计.md。"
fi

{
  echo "# 磁盘巡检 $TS"
  echo
  echo "数据卷 \`$VOL\`：总 $(gb "$SIZE_K")，已用 $(gb "$USED_K")（$PCT%），可用 $(gb "$AVAIL_K")，较上次 ${AVAIL_DELTA}。"
  [ -n "$ALERT" ] && { echo; echo "$ALERT"; }
  echo
  echo "| # | 档 | 路径 | 实际占用 | 较上次 | 它是什么 | 建议清理方式 |"
  echo "|---|---|---|---|---|---|---|"
  printf '%s' "$ROWS"
  echo
  [ -n "$SNAP_NOTE" ] && echo "$SNAP_NOTE"
  echo
  echo "说明：本报告由 scan.sh 只读生成，未删除任何文件。占用用 du 实测，虚拟磁盘的显示大小单独标注。档位 X 只监控、不清理。"
  [ -n "$PREV_TSV" ] && echo "对比基线：$(basename "$PREV_TSV" .tsv)。" || echo "首次运行，无对比基线。"
} >"$OUT_MD"
cp "$OUT_MD" "$REPORT_DIR/latest.md"

if [ -n "$ALERT" ] && [ "$(uname)" = Darwin ] && [ "${DISK_GUARD_NOTIFY:-1}" = 1 ]; then
  ( osascript -e "display notification \"可用 ${AVAIL_GB}G / 占用 ${PCT}%，报告见 ~/.disk-guard/reports/latest.md\" with title \"磁盘巡检提醒\"" >/dev/null 2>&1 & )
fi
echo "$OUT_MD"
