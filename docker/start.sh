#!/usr/bin/env bash
# ==============================================================

set -euo pipefail

# docker/ 目录的绝对路径
DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（docker/ 的上级）
PROJECT_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"
# 容器内项目路径
HERMES_AGENT_DIR_IN_CONTAINER="/app/patent-hermes-agent"

CONTAINER_NAME="${CONTAINER_NAME:-patent-hermes-agent}"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"

# ---------- 工具 ----------
log()  { printf '\033[1;36m[start]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[start]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[start]\033[0m %s\n' "$*" >&2; }

# ---------- Pre-flight ----------
log "[0/4] Pre-flight 检查..."

if ! command -v docker >/dev/null 2>&1; then
    err "未安装 Docker。请先安装 Docker。"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    err "Docker 守护进程未启动。请先启动 Docker。"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    err "docker compose 不可用。请升级 Docker。"
    exit 1
fi

if [ ! -f "${DOCKER_DIR}/.env" ]; then
    err ".env 文件不存在。请先执行：cd docker && cp .env.example .env  然后把 API Key 填上。"
    exit 1
fi

if [ ! -d "${PROJECT_ROOT}/scripts" ]; then
    err "找不到项目 scripts 目录：${PROJECT_ROOT}/scripts"
    exit 1
fi

if [ ! -x "${PROJECT_ROOT}/scripts/start.sh" ]; then
    chmod +x "${PROJECT_ROOT}/scripts/start.sh" 2>/dev/null || true
fi

# ---------- 确保基础镜像存在（国内自动从华为云拉，自动匹配宿主机架构） ----------
if ! docker image inspect python:3.11-slim >/dev/null 2>&1; then
    ARCH="$(uname -m)"
    log "本地没有 python:3.11-slim，从华为云镜像拉取（架构：${ARCH}）..."
    MIRROR_URL="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim-${ARCH}"
    if docker pull "$MIRROR_URL"; then
        docker tag "$MIRROR_URL" python:3.11-slim
        log "基础镜像就位。"
    else
        log "华为云架构标签不可用，尝试不带架构标签的通用地址..."
        MIRROR_URL="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim"
        if docker pull "$MIRROR_URL"; then
            docker tag "$MIRROR_URL" python:3.11-slim
            log "基础镜像就位。"
        else
            err "国内镜像源都拉取失败，请检查网络或手动执行："
            err "  docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim"
            err "  docker tag swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/python:3.11-slim python:3.11-slim"
            exit 1
        fi
    fi
fi

# 加载 .env 到本脚本进程
set -a
# shellcheck disable=SC1091
source "${DOCKER_DIR}/.env"
set +a

DASHBOARD_HOST_PORT="${DASHBOARD_HOST_PORT:-9130}"
GATEWAY_HOST_PORT="${GATEWAY_HOST_PORT:-8790}"
OUTPUT_HOST_PORT="${OUTPUT_HOST_PORT:-9131}"

# ---------- 容器状态机 ----------
_raw_state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
container_state="$(echo "${_raw_state}" | tr -d '[:space:]')"
: "${container_state:=missing}"

case "$container_state" in
  missing)
    log "[1/4] 容器不存在，构建镜像并创建容器..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d --build
    ;;
  exited|created)
    log "[1/4] 容器已停止，启动..."
    docker compose -f "$COMPOSE_FILE" start
    ;;
  running)
    log "[1/4] 容器已在运行"
    ;;
  *)
    warn "容器状态异常：${container_state}，尝试 up..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d
    ;;
esac

# ---------- 等容器就绪 ----------
log "[2/4] 等待容器内 hermes 就绪..."
ready=0
for i in $(seq 1 20); do
 if docker exec "$CONTAINER_NAME" hermes --version >/dev/null 2>&1; then
   ready=1
   break
 fi
 sleep 2
done

if [ "$ready" -ne 1 ]; then
 err "容器在 40 秒内未就绪。可以查看日志排查：docker logs $CONTAINER_NAME"
 exit 1
fi

hermes_version="$(docker exec "$CONTAINER_NAME" hermes --version 2>/dev/null | head -1 || echo '?')"
log "    容器内 hermes：${hermes_version}"

# ---------- 配置模型（幂等，每次启动都跑一遍以同步 .env 改动）----------
log "[3/4] 配置模型..."

# 把配置值写到临时文件（通过挂载目录中转），Python 脚本读文件写入 config.yaml
# 兼容 bash 3.2（macOS 自带版本）
printf '%s' "${HERMES_MODEL_DEFAULT:-MiniMax-M2.7}" > "${PROJECT_ROOT}/.tmp_m_default"
printf '%s' "${HERMES_MODEL_PROVIDER:-minimax-cn}" > "${PROJECT_ROOT}/.tmp_m_provider"
printf '%s' "${HERMES_MODEL_BASE_URL:-https://api.minimaxi.com/anthropic}" > "${PROJECT_ROOT}/.tmp_m_base_url"
printf '%s' "${HERMES_MODEL_API_KEY:-${OPENAI_API_KEY:-}}" > "${PROJECT_ROOT}/.tmp_m_api_key"

# 写 Python 脚本到挂载目录，容器内直接执行（避免 docker exec heredoc 不工作）
cat > "${PROJECT_ROOT}/.tmp_set_config.py" <<'PYEOF'
import pathlib, yaml

base = '/app/patent-hermes-agent'
p = pathlib.Path('/root/.hermes/config.yaml')
cfg = yaml.safe_load(p.read_text()) if p.exists() else {}
cfg = cfg or {}

def read_tmp(name):
    f = pathlib.Path(f'{base}/.tmp_m_{name}')
    return f.read_text() if f.exists() else ''

cfg.setdefault('model', {})
cfg['model']['default'] = read_tmp('default')
cfg['model']['provider'] = read_tmp('provider')
cfg['model']['base_url'] = read_tmp('base_url')
cfg['model']['max_tokens'] = 32768

api_key = read_tmp('api_key')
if api_key.strip():
    cfg['model']['api_key'] = api_key

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))

# 验证
cfg2 = yaml.safe_load(p.read_text())
model = cfg2.get('model', {})
key = model.get('api_key', '')
print(f"  model.default = {model.get('default', '(empty)')}")
print(f"  model.provider = {model.get('provider', '(empty)')}")
print(f"  model.base_url = {model.get('base_url', '(empty)')}")
if key:
    print(f"  model.api_key = {key[:20]}...({len(key)} chars)")
else:
    print("  model.api_key = (empty!)")
PYEOF

docker exec "$CONTAINER_NAME" python3 /app/patent-hermes-agent/.tmp_set_config.py
rm -f "${PROJECT_ROOT}/.tmp_set_config.py"
rm -f "${PROJECT_ROOT}/.tmp_m_default" "${PROJECT_ROOT}/.tmp_m_provider" \
      "${PROJECT_ROOT}/.tmp_m_base_url" "${PROJECT_ROOT}/.tmp_m_api_key"

# 调优参数
docker exec "$CONTAINER_NAME" python3 <<'PY' >/dev/null
import pathlib, yaml

p = pathlib.Path('/root/.hermes/config.yaml')
cfg = yaml.safe_load(p.read_text()) if p.exists() else {}
cfg = cfg or {}

cfg.setdefault('delegation', {})['child_timeout_seconds'] = 1200
cfg['delegation']['max_concurrent_children'] = 3

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))
print('[config] delegation params set')
PY

# ---------- 启动 Hermes Agent ----------
log "[4/4] 在容器内启动 Hermes Agent..."
docker exec "$CONTAINER_NAME" bash "$HERMES_AGENT_DIR_IN_CONTAINER/scripts/start.sh" 2>&1 || true

# 杀掉项目 start.sh 可能启动的 dashboard（绑定 127.0.0.1，宿主机访问不到）
docker exec "$CONTAINER_NAME" hermes dashboard --stop 2>/dev/null || true

log "    启动 Gateway..."
docker exec -d "$CONTAINER_NAME" hermes gateway run --accept-hooks -q

log "    启动 Dashboard（0.0.0.0:9119）..."
docker exec -d "$CONTAINER_NAME" hermes dashboard --no-open --host 0.0.0.0 --insecure --skip-build

log "    启动 Output 文件服务（0.0.0.0:9131，仅暴露 output/）..."
docker exec "$CONTAINER_NAME" pkill -f "http.server 9131" 2>/dev/null || true
docker exec "$CONTAINER_NAME" mkdir -p "$HERMES_AGENT_DIR_IN_CONTAINER/output"
docker exec -d "$CONTAINER_NAME" python3 -m http.server 9131 --directory "$HERMES_AGENT_DIR_IN_CONTAINER/output"

sleep 5
docker exec "$CONTAINER_NAME" hermes gateway status 2>&1 || true
docker exec "$CONTAINER_NAME" hermes dashboard --status 2>&1 || true

# ---------- 完成 ----------
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