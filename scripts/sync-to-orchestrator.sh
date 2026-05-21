#!/usr/bin/env bash
# ==============================================================
# sync-to-orchestrator.sh
# 将 patent-hermes 的 agents / skills / knowledge 同步到
# claude-agent-orchestrator/.claude/ 目录
#
# 用法：./scripts/sync-to-orchestrator.sh [--dry-run]
#
# 以 patent-hermes 为源（单点维护），单向同步到 orchestrator。
# 同步方式：rsync --delete，保证目标目录与源完全一致。
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 目标项目路径（同级目录下的 claude-agent-orchestrator）
ORCHESTRATOR_ROOT="$(cd "${HERMES_ROOT}/../claude-agent-orchestrator" && pwd)"
ORCHESTRATOR_CLAUDE="${ORCHESTRATOR_ROOT}/.claude"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] 以下操作仅模拟，不会实际修改文件"
fi

# ---------- 工具 ----------
log()  { printf '\033[1;36m[sync]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[sync]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[sync]\033[0m %s\n' "$*" >&2; }

# ---------- 前置检查 ----------
if [ ! -d "$ORCHESTRATOR_ROOT" ]; then
  err "目标项目不存在：${ORCHESTRATOR_ROOT}"
  err "请确认 claude-agent-orchestrator 与 patent-hermes 在同一父目录下"
  exit 1
fi

if [ ! -d "$ORCHESTRATOR_CLAUDE" ]; then
  err "目标 .claude 目录不存在：${ORCHESTRATOR_CLAUDE}"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  err "rsync 未安装。请先安装：brew install rsync（macOS）或 apt install rsync（Linux）"
  exit 1
fi

# ---------- 构造 rsync 参数 ----------
RSYNC_OPTS="-avz --delete --exclude='.DS_Store' --exclude='__pycache__'"
if $DRY_RUN; then
  RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi

# ---------- 同步 ----------
log "源项目  : ${HERMES_ROOT}"
log "目标项目: ${ORCHESTRATOR_CLAUDE}"
log ""

# 1) agents/
SRC="${HERMES_ROOT}/agents/"
DEST="${ORCHESTRATOR_CLAUDE}/agents/"
log "[1/3] 同步 agents/ → ${DEST}"
rsync ${RSYNC_OPTS} "${SRC}" "${DEST}"
log ""

# 2) skills/
SRC="${HERMES_ROOT}/skills/"
DEST="${ORCHESTRATOR_CLAUDE}/skills/"
log "[2/3] 同步 skills/ → ${DEST}"
rsync ${RSYNC_OPTS} "${SRC}" "${DEST}"
log ""

# 3) knowledge/
SRC="${HERMES_ROOT}/knowledge/"
DEST="${ORCHESTRATOR_CLAUDE}/knowledge/"
log "[3/3] 同步 knowledge/ → ${DEST}"
rsync ${RSYNC_OPTS} "${SRC}" "${DEST}"
log ""

# ---------- 完成 ----------
if $DRY_RUN; then
  warn "dry-run 完成。以上操作未实际执行。去掉 --dry-run 参数即可正式同步。"
else
  log "同步完成。agents / skills / knowledge 已与 claude-agent-orchestrator 保持一致。"
  log ""
  log "提示："
  log "  - 日常修改只在 patent-hermes 中进行，改完后跑本脚本即可同步"
  log "  - 如需反向同步（orchestrator → hermes），请勿用此脚本，需手动处理"
  log "  - 可加入 git pre-commit hook 自动触发同步"
fi