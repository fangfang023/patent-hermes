#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# ─── 加载 scripts/.env ───
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

# ─── 加载共享工具 ───
# shellcheck source=lib/detect_hermes_python.sh
. "$SCRIPTS_DIR/lib/detect_hermes_python.sh"

# 给 hooks 脚本加可执行权限（git 拉下来后可能丢失）
chmod +x "$PROJECT_ROOT"/hooks/*.sh 2>/dev/null || true

LOG_DIR="$PROJECT_ROOT/.logs"
mkdir -p "$LOG_DIR"

# ─── [0/4] 注册项目插件 → ~/.hermes/plugins/ ───
echo "[0/4] 注册项目插件..."
"$SCRIPTS_DIR/register-plugins.sh"

# ─── [1/4] 初始化 Hermes 配置（共享模块）───
echo "[1/4] 初始化 Hermes 配置..."
"$HERMES_PY" "$SCRIPTS_DIR/hermes_init.py" --project-dir "$PROJECT_ROOT"

# ─── [2/4] 启动 Hermes Gateway ───
echo "[2/4] 启动 Hermes Gateway..."
hermes gateway start

# ─── [3/4] 启动 Dashboard ───
echo "[3/4] 启动 Dashboard..."
DASHBOARD_LOG="$LOG_DIR/dashboard.log"
if lsof -i :"$DASHBOARD_PORT" >/dev/null 2>&1; then
  echo "Dashboard 已在运行(端口 $DASHBOARD_PORT),跳过重复启动。"
else
  hermes dashboard --no-open --port "$DASHBOARD_PORT" >"$DASHBOARD_LOG" 2>&1 &
  for _ in 1 2 3 4 5; do
    sleep 1
    if lsof -i :"$DASHBOARD_PORT" >/dev/null 2>&1; then
      echo "Dashboard 已启动。"
      break
    fi
  done
fi

echo "当前状态："
hermes gateway status || true

if lsof -i :"$DASHBOARD_PORT" >/dev/null 2>&1; then
  if command -v open >/dev/null 2>&1; then
    open "http://127.0.0.1:$DASHBOARD_PORT/" || true
  fi
else
  echo "Dashboard 似乎未成功启动，请查看日志：$DASHBOARD_LOG"
fi

# ─── [4/4] 启动 Output 文件服务 ───
echo "[4/4] 启动 Output 文件服务（http://127.0.0.1:${OUTPUT_PORT}，仅暴露 output/）..."
mkdir -p "$PROJECT_ROOT/output"
pkill -f "http.server $OUTPUT_PORT" 2>/dev/null || true
python3 -m http.server "$OUTPUT_PORT" --directory "$PROJECT_ROOT/output" >"$LOG_DIR/output-server.log" 2>&1 &
echo "Output 文件服务已启动：http://127.0.0.1:$OUTPUT_PORT"

echo "启动完成。"