#!/usr/bin/env bash
# ==============================================================
# Patent Hermes Agent · Docker 部署启动脚本
# 配置唯一来源：docker/.env → env_file 注入容器环境变量
# 本脚本独立完成容器内所有初始化，不调用 scripts/start.sh
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
log "[0/7] Pre-flight 检查..."

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

# 加载 docker/.env 到本脚本进程
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
    log "[1/7] 容器不存在，构建镜像并创建容器..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d --build
    ;;
  exited|created)
    log "[1/7] 容器已停止，启动..."
    docker compose -f "$COMPOSE_FILE" start
    ;;
  running)
    log "[1/7] 容器已在运行"
    ;;
  *)
    warn "容器状态异常：${container_state}，尝试 up..."
    DOCKER_BUILDKIT=0 docker compose -f "$COMPOSE_FILE" up -d
    ;;
esac

# ---------- 等容器就绪 ----------
log "[2/7] 等待容器内 hermes 就绪..."
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

# ---------- 配置模型 + 调优参数 ----------
log "[3/7] 配置模型..."

# 把配置值写到临时文件（通过挂载目录中转），Python 脚本读文件写入 config.yaml
# 兼容 bash 3.2（macOS 自带版本）
printf '%s' "${HERMES_MODEL_DEFAULT:-MiniMax-M2.7}" > "${PROJECT_ROOT}/.tmp_m_default"
printf '%s' "${HERMES_MODEL_PROVIDER:-minimax-cn}" > "${PROJECT_ROOT}/.tmp_m_provider"
printf '%s' "${HERMES_MODEL_BASE_URL:-https://api.minimaxi.com/anthropic}" > "${PROJECT_ROOT}/.tmp_m_base_url"
printf '%s' "${HERMES_MODEL_API_KEY:-${OPENAI_API_KEY:-}}" > "${PROJECT_ROOT}/.tmp_m_api_key"

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

# 调优参数（合并到同一步骤，减少 docker exec 次数）
cfg.setdefault('delegation', {})['child_timeout_seconds'] = 1200
cfg['delegation']['max_concurrent_children'] = 3
cfg['terminal'] = {'cwd': base}

# credential_pool_strategies
cfg.setdefault('credential_pool_strategies', {})['zai'] = 'round_robin'

# providers timeout
cfg.setdefault('providers', {}).setdefault('zai', {})['request_timeout_seconds'] = 300

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

# ---------- 同步飞书变量到 ~/.hermes/.env ----------
log "[4/7] 同步飞书变量到 ~/.hermes/.env..."

# 需要从 docker/.env（已注入为容器环境变量）同步到 ~/.hermes/.env 的变量列表
SYNC_VARS=(
  HERMES_MODEL_API_KEY
  MINIMAX_CN_API_KEY
  MINIMAX_CN_BASE_URL
  OPENAI_API_KEY
  FEISHU_APP_ID
  FEISHU_APP_SECRET
  FEISHU_DOMAIN
  FEISHU_CONNECTION_MODE
  FEISHU_GROUP_POLICY
  GATEWAY_ALLOW_ALL_USERS
  FEISHU_ALLOW_ALL_USERS
  FEISHU_ALLOWED_USERS
)

# 把 SYNC_VARS 和它们的值写到临时文件，容器内 Python 脚本读取后写入 ~/.hermes/.env
# 这样避免在宿主机处理容器内文件路径问题
TMP_ENV_LINES=""
for VAR in "${SYNC_VARS[@]}"; do
    VAL="${!VAR:-}"
    TMP_ENV_LINES="${TMP_ENV_LINES}${VAR}=${VAL}\n"
done

printf '%s\n' "$TMP_ENV_LINES" > "${PROJECT_ROOT}/.tmp_sync_env.txt"

cat > "${PROJECT_ROOT}/.tmp_sync_env.py" <<'PYEOF'
import pathlib

base = '/app/patent-hermes-agent'
hermes_env_path = pathlib.Path('/root/.hermes/.env')
src_path = pathlib.Path(f'{base}/.tmp_sync_env.txt')

# 读入要同步的变量
sync_lines = src_path.read_text().strip().split('\n') if src_path.exists() else []
sync_vars = {}
for line in sync_lines:
    if '=' in line:
        k, v = line.split('=', 1)
        sync_vars[k] = v

# 读入已有的 ~/.hermes/.env
existing_lines = []
if hermes_env_path.exists():
    existing_lines = hermes_env_path.read_text().strip().split('\n')

# 合并：已存在的变量替换值，新变量追加
merged = {}
for line in existing_lines:
    if '=' in line:
        k, v = line.split('=', 1)
        merged[k] = v

for k, v in sync_vars.items():
    merged[k] = v

hermes_env_path.parent.mkdir(parents=True, exist_ok=True)
hermes_env_path.write_text('\n'.join(f'{k}={v}' for k, v in merged.items()) + '\n')

print(f"  已同步 {len(sync_vars)} 个变量到 ~/.hermes/.env")
for k in sorted(sync_vars.keys()):
    v = sync_vars[k]
    if v:
        print(f"    {k} = {v[:20]}...({len(v)} chars)")
    else:
        print(f"    {k} = (empty)")
PYEOF

docker exec "$CONTAINER_NAME" python3 /app/patent-hermes-agent/.tmp_sync_env.py
rm -f "${PROJECT_ROOT}/.tmp_sync_env.py" "${PROJECT_ROOT}/.tmp_sync_env.txt"

# ---------- 挂载 Skills 到 Hermes ----------
log "[5/7] 挂载项目级 Skills 到 Hermes..."

cat > "${PROJECT_ROOT}/.tmp_mount_skills.py" <<'PYEOF'
import sys, json, pathlib, yaml

target = '/app/patent-hermes-agent/skills'
cfg_path = pathlib.Path('/root/.hermes/config.yaml')
cfg = yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}
cfg = cfg or {}
sk = cfg.setdefault('skills', {})
cur = sk.get('external_dirs')
if isinstance(cur, str):
    try:
        parsed = json.loads(cur)
        new_list = parsed if isinstance(parsed, list) else [str(parsed)]
    except json.JSONDecodeError:
        new_list = [cur]
elif isinstance(cur, list):
    new_list = list(cur)
else:
    new_list = []
if target not in new_list:
    new_list.append(target)
seen=set(); new_list=[x for x in new_list if not (x in seen or seen.add(x))]
sk['external_dirs'] = new_list
cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))
print(f'  skills.external_dirs => {new_list}')
PYEOF

docker exec "$CONTAINER_NAME" python3 /app/patent-hermes-agent/.tmp_mount_skills.py
rm -f "${PROJECT_ROOT}/.tmp_mount_skills.py"

# ---------- Patch Hermes ----------
log "[6/7] Patch Hermes: 启用 parallel_tool_calls + 禁用 Anthropic SDK 内部重试..."

# 容器内 hermes-agent 通过 pip 安装到 site-packages，需要动态定位路径
cat > "${PROJECT_ROOT}/.tmp_patch_hermes.py" <<'PYEOF'
import pathlib, importlib, sys

# ---- Patch 1: parallel_tool_calls ----
# 动态定位 chat_completions.py
try:
    from hermes_agent.agent.transports import chat_completions as _cc_mod
    target1 = pathlib.Path(_cc_mod.__file__)
except (ImportError, AttributeError):
    # fallback: 尝试从 venv 或 site-packages 查找
    target1 = None

if target1 and target1.exists():
    src = target1.read_text()
    marker = 'api_kwargs["parallel_tool_calls"] = True'
    if marker in src:
        print("  [patch] parallel_tool_calls=True 已存在，跳过")
    else:
        old1 = '''            api_kwargs["tools"] = tools

        # max_tokens resolution — priority: ephemeral > user > provider default'''
        new1 = '''            api_kwargs["tools"] = tools
            api_kwargs["parallel_tool_calls"] = True

        # max_tokens resolution — priority: ephemeral > user > provider default'''

        old2 = '''            api_kwargs["tools"] = tools

        # max_tokens resolution — priority: ephemeral > user > profile default'''
        new2 = '''            api_kwargs["tools"] = tools
            api_kwargs["parallel_tool_calls"] = True

        # max_tokens resolution — priority: ephemeral > user > profile default'''

        patched = src
        count = 0
        if old1 in patched:
            patched = patched.replace(old1, new1, 1)
            count += 1
        if old2 in patched:
            patched = patched.replace(old2, new2, 1)
            count += 1

        if count >= 1:
            target1.write_text(patched)
            print(f"  [patch] 成功在 {count} 处插入 parallel_tool_calls=True")
        else:
            print("  [patch] 未找到匹配的插入点（可能已被修改或 Hermes 版本变更），跳过")
else:
    print(f"  [patch] chat_completions.py 未找到，跳过")

# ---- Patch 2: disable Anthropic SDK internal retries ----
try:
    from hermes_agent.agent import anthropic_adapter as _aa_mod
    target2 = pathlib.Path(_aa_mod.__file__)
except (ImportError, AttributeError):
    target2 = None

if target2 and target2.exists():
    src2 = target2.read_text()
    marker2 = 'max_retries=0  # patched: disable SDK internal retries'
    if marker2 in src2:
        print("  [patch] anthropic max_retries=0 已存在，跳过")
    else:
        old = '    return _anthropic_sdk.Anthropic(**kwargs)'
        new = '    kwargs["max_retries"] = 0  # patched: disable SDK internal retries\n    return _anthropic_sdk.Anthropic(**kwargs)'
        if old in src2:
            target2.write_text(src2.replace(old, new, 1))
            print("  [patch] anthropic_adapter.py: max_retries=0 已插入，禁用 SDK 内部重试")
        else:
            print("  [patch] 未找到插入点（可能已被修改），跳过")
else:
    print(f"  [patch] anthropic_adapter.py 未找到，跳过")
PYEOF

docker exec "$CONTAINER_NAME" python3 /app/patent-hermes-agent/.tmp_patch_hermes.py
rm -f "${PROJECT_ROOT}/.tmp_patch_hermes.py"

# ---------- 启动 Hermes Agent ----------
log "[7/7] 启动 Hermes Agent..."

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