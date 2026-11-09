# disk-guard：Agent 时代的磁盘管理

两层分工：脚本每周只读测量（零 token、零删除）；Agent 只在需要时出场，先审计、再按编号清理。
方法参考 [riza/ai-disk-cleanup](https://github.com/riza/ai-disk-cleanup)。该仓库未设许可证，本套提示词与脚本为重新撰写，未复制其原文。

## 安装（macOS）

```bash
git clone https://github.com/markwaveio/disk-guard.git ~/disk-guard && ~/disk-guard/install.sh
```

安装会注册每周一 09:30 的 launchd 任务，建立 `~/.disk-guard` 指向安装目录，并立即跑一次巡检生成基线。
卸载：`~/disk-guard/install.sh uninstall`（报告保留）。
Linux 没有 launchd，用 cron：`30 9 * * 1 ~/disk-guard/scripts/scan.sh`。

## 目录

| 路径 | 作用 |
|---|---|
| `SKILL.md` | Agent 技能入口（Hermes / Claude Code / Codex 可加载） |
| `scripts/scan.sh` | 只读巡检。测盯盘清单的实际占用，对比上次，写 `reports/<日期>.md` 和 `latest.md`；越过阈值时弹 macOS 通知 |
| `config/paths.conf` | 盯盘清单：档位、路径、说明、建议清理方式。增删路径改这里 |
| `prompts/01-只读审计.md` | 贴给 Agent：读 latest.md → 下钻 → 出编号表，不删任何东西 |
| `prompts/02-按编号清理.md` | 贴给 Agent：只删你点名的编号，逐项报释放量，最后刷新基线 |
| `prompts/03-项目约定片段.md` | 贴进各项目 AGENTS.md / CLAUDE.md，从源头少产垃圾 |
| `launchd/com.markwave.disk-guard.plist` | 定时模板：每周一 09:30 |
| `install.sh` | 安装定时；`./install.sh uninstall` 卸载 |
| `reports/` `logs/` | 本机生成，不进仓库 |

## 日常流程

1. 每周一 09:30 自动跑 `scan.sh`，看 `~/.disk-guard/reports/latest.md`。
2. 收到通知（默认：可用 < 50G 或占用 ≥ 85%），或某项「较上次」涨得多 → 在 Agent 里贴 `01`。
3. 读审计表，挑编号 → 贴 `02`。
4. 清理完 `02` 会自动重跑 `scan.sh` 刷新基线。

## 调整

- 阈值：`DISK_GUARD_WARN_AVAIL_GB`、`DISK_GUARD_WARN_USED_PCT`（在 plist 里加 `EnvironmentVariables`）。
- 项目根：`DISK_GUARD_PROJECT_ROOT`，默认 `~/Cursor`（统计 node_modules / .venv）。
- 改频率：改 plist 的 `StartCalendarInterval` 后重新 `./install.sh`。
- 手动跑：`~/.disk-guard/scripts/scan.sh`；立即触发定时任务：`launchctl kickstart gui/$(id -u)/com.markwave.disk-guard`。

## 安全边界与已知限制

- `scan.sh` 只执行 `df / du / find / stat / tmutil list`，只写 `reports/` 和 `logs/`。
- 档位 X（`~/.hermes` `~/.codex` `~/.claude`）只监控，不给清理建议。
- launchd 后台运行时，macOS 隐私权限会拒读 `~/Downloads` 和 `~/.Trash`，报告显示「无权限/不存在」；前台手动跑或 01 审计时能读到。
- 「等我批准」只是提示词里的话。Agent 必须在逐条确认的权限模式下跑，不要开自动批准。
- 终端删除不进回收站。批准 2 档前先确认备份。
