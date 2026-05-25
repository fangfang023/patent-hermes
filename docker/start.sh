#!/usr/bin/env bash
# ==============================================================
# Patent Hermes Agent · Docker 部署启动脚本
# 配置唯一来源：docker/.env → env_file 注入容器环境变量
# 初始化逻辑由 scripts/hermes_init.py 共享模块完成
# ==============================================================

set -euo pipefail

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"
HERMES_AGENT_DIR_IN_CONTAINER="/app/patent-hermes-agent"

CONTAINER_NAME="${CONTAINER_NAME:-patent-hermes-agent}"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"

# ---------- 工具 ----------
log()  { printf '\033[1;36m[start]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[start]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[start]\033[0m %s\n' "$*" >&2; }

# ---------- Pre-flight ----------
log "[0/5] Pre-flight 检查..."

if ! command -v docker >/dev/null 2>&1; then
    err "未安装 Docker。请先安装 Docker。" && exit 1
fi
if ! docker info >/dev/null 2>&1; then
    err "Docker 守护进程未启动。请先启动 Docker。" && exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
    err "docker compose 不可用。请升级 Docker。" && exit 1
fi
if [ ! -f "${DOCKER_DIR}/.env" ]; then
    err ".env 文件不存在。请先执行：cd docker && cp .env.example .env  然后把 API Key 填上。" && exit 1
fi

# ---------- 确保基础镜像存在（国内华为云镜像） ----------
if ! docker image inspect python:3.11-slim >/dev/null 2>&1; then
    ARCH="$(uname -m)"
    log "本地没有 python:3.11-slim，从华为云镜像拉取（架构：${ARCH}）..."
    MIRROR_URL="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim-${ARCH}"
    if docker pull "$MIRROR_URL"; then
        docker tag "$MIRROR_URL" python:3.11-slim && log "基础镜像就位。"
    else
        log "华为云架构标签不可用，尝试不带架构标签的通用地址..."
        MIRROR_URL="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim"
        if docker pull "$MIRROR_URL"; then
            docker tag "$MIRROR_URL" python:3.11-slim && log "基础镜像就位。"
        else
            err "国内镜像源都拉取失败，请检查网络或手动执行："
            err "  docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim"
            err "  docker tag ... python:3.11-slim" && exit 1
        fi
    fi
fi

# ---------- 加载 docker/.env ----------
set -a
# shellcheck disable=SC1091
source "${DOCKER_DIR}/.env"
set +a

: "${DASHBOARD_HOST_PORT?未设置 DASHBOARD_HOST_PORT，请在 docker/.env 中配置}"
: "${GATEWAY_HOST_PORT?未设置 GATEWAY_HOST_PORT，请在 docker/.env 中配置}"
: "${OUTPUT_HOST_PORT?未设置 OUTPUT_HOST_PORT，请在 docker/.env 中配置}"
: "${DASHBOARD_CONTAINER_PORT?未设置 DASHBOARD_CONTAINER_PORT，请在 docker/.env 中配置}"
: "${GATEWAY_CONTAINER_PORT?未设置 GATEWAY_CONTAINER_PORT，请在 docker/.env 中配置}"
: "${OUTPUT_CONTAINER_PORT?未设置 OUTPUT_CONTAINER_PORT，请在 docker/.env 中配置}"

# ---------- 容器状态机 ----------
_raw_state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
container_state="$(echo "${_raw_state}" | tr -d '[:space:]')"
: "${container_state:=missing}"

case "$container_state" in
  missing)
    log "[1/5] 容器不存在，构建镜像并创建容器..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d --build
    ;;
  exited|created)
    log "[1/5] 容器已停止，启动..."
    docker compose -f "$COMPOSE_FILE" start
    ;;
  running)
    log "[1/5] 容器已在运行"
    ;;
  *)
    warn "容器状态异常：${container_state}，尝试 up..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d
    ;;
esac

# ---------- 等容器就绪 ----------
log "[2/5] 等待容器内 hermes 就绪..."
ready=0
for i in $(seq 1 20); do
 if docker exec "$CONTAINER_NAME" hermes --version >/dev/null 2>&1; then
   ready=1 && break
 fi
 sleep 2
done

if [ "$ready" -ne 1 ]; then
 err "容器在 40 秒内未就绪。可以查看日志排查：docker logs $CONTAINER_NAME" && exit 1
fi

hermes_version="$(docker exec "$CONTAINER_NAME" hermes --version 2>/dev/null | head -1 || echo '?')"
log "    容器内 hermes：${hermes_version}"

# ---------- 注册项目插件 ----------
log "[2.5/5] 注册项目插件到容器内 ~/.hermes/plugins/..."
PLUGINS_DIR_IN_CONTAINER="${HERMES_AGENT_DIR_IN_CONTAINER}/plugins"
HERMES_PLUGINS_IN_CONTAINER="/root/.hermes/plugins"
docker exec "$CONTAINER_NAME" mkdir -p "$HERMES_PLUGINS_IN_CONTAINER"
for plugin_dir in plugins/*/; do
  [ -d "$plugin_dir" ] || continue
  plugin_name=$(basename "$plugin_dir")
  [ -f "$plugin_dir/plugin.yaml" ] || continue
  docker exec "$CONTAINER_NAME" ln -sfn \
    "${PLUGINS_DIR_IN_CONTAINER}/${plugin_name}" \
    "${HERMES_PLUGINS_IN_CONTAINER}/${plugin_name}"
  log "    ✓ ${plugin_name}"
done

# ---------- 启用项目所需插件（Hermes opt-in 机制） ----------
for plugin in document-processor; do
  docker exec "$CONTAINER_NAME" hermes plugins enable "$plugin" 2>/dev/null && \
    log "    ✓ ${plugin} 已启用" || \
    warn "    ⚠ ${plugin} 启用失败，可能需要手动执行"
done

# ---------- 初始化 Hermes 配置（共享模块） ----------
log "[3/5] 初始化 Hermes 配置..."
# docker/.env 已通过 env_file 注入为容器环境变量，hermes_init.py 直接从环境变量读值
docker exec "$CONTAINER_NAME" python3 \
  "${HERMES_AGENT_DIR_IN_CONTAINER}/scripts/hermes_init.py" \
  --project-dir "$HERMES_AGENT_DIR_IN_CONTAINER" \
  --home-dir "/root/.hermes"

# ---------- 启动 Hermes Agent ----------
log "[4/5] 启动 Hermes Agent..."

# 先杀掉可能残留的旧进程
docker exec "$CONTAINER_NAME" pkill -f "hermes gateway" 2>/dev/null || true
docker exec "$CONTAINER_NAME" pkill -f "hermes dashboard" 2>/dev/null || true
docker exec "$CONTAINER_NAME" pkill -f "http.server" 2>/dev/null || true

log "    启动 Gateway..."
docker exec -d "$CONTAINER_NAME" hermes gateway run --accept-hooks -q

log "    启动 Dashboard（0.0.0.0:${DASHBOARD_CONTAINER_PORT}）..."
docker exec -d "$CONTAINER_NAME" hermes dashboard --no-open --host 0.0.0.0 --port "$DASHBOARD_CONTAINER_PORT" --insecure --skip-build

log "    启动 Output 文件服务（0.0.0.0:${OUTPUT_CONTAINER_PORT}，仅暴露 output/）..."
docker exec "$CONTAINER_NAME" mkdir -p "$HERMES_AGENT_DIR_IN_CONTAINER/output"
docker exec -d "$CONTAINER_NAME" python3 -m http.server "$OUTPUT_CONTAINER_PORT" --directory "$HERMES_AGENT_DIR_IN_CONTAINER/output"

sleep 5
docker exec "$CONTAINER_NAME" hermes gateway status 2>&1 || true

# ---------- 完成 ----------
log "[5/5] 完成。"

cat <<EOF

============================================================
  Patent Hermes Agent 已启动
  -------------------------------------------
  Dashboard   : http://localhost:${DASHBOARD_HOST_PORT}
  Gateway     : http://localhost:${GATEWAY_HOST_PORT}
  Output Files: http://localhost:${OUTPUT_HOST_PORT}
  容器名      : ${CONTAINER_NAME}
  -------------------------------------------
  进入容器  : docker exec -it ${CONTAINER_NAME} bash
  看日志    : docker logs -f ${CONTAINER_NAME}
  关闭      : ./stop.sh
============================================================

EOF