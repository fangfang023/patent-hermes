#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 加载共享工具
# shellcheck source=lib/detect_hermes_python.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/detect_hermes_python.sh"

echo "[1/3] 停止 Hermes Gateway..."
hermes gateway stop || true

echo "[2/3] 停止 Hermes Dashboard..."
if ! hermes dashboard --stop; then
  hermes dashboard stop || true
fi

echo "[3/3] 停止 Output 文件服务..."
pkill -f "http.server 9131" 2>/dev/null || true

echo "当前状态："
hermes gateway status || true
hermes dashboard --status || true

echo "关闭完成。"