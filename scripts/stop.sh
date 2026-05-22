#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 加载 scripts/.env 中的端口配置
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPTS_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
else
  echo "错误：未找到 scripts/.env，请先执行：cd scripts && cp .env.example .env" >&2
  exit 1
fi
: "${DASHBOARD_PORT?未设置 DASHBOARD_PORT，请在 scripts/.env 中配置}"
: "${OUTPUT_PORT?未设置 OUTPUT_PORT，请在 scripts/.env 中配置}"

# 加载共享工具
# shellcheck source=lib/detect_hermes_python.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/detect_hermes_python.sh"

echo "[1/3] 停止 Hermes Gateway..."
hermes gateway stop || true

echo "[2/3] 停止 Hermes Dashboard..."
pkill -f "hermes dashboard" 2>/dev/null || true

echo "[3/3] 停止 Output 文件服务..."
pkill -f "http.server $OUTPUT_PORT" 2>/dev/null || true

echo "当前状态："
hermes gateway status || true

echo "关闭完成。"