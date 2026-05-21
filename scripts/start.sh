#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 加载共享工具
# shellcheck source=lib/detect_hermes_python.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/detect_hermes_python.sh"

# 给 hooks 脚本加可执行权限（git 拉下来后可能丢失）
chmod +x "$PROJECT_ROOT"/hooks/*.sh 2>/dev/null || true

LOG_DIR="$PROJECT_ROOT/.logs"
mkdir -p "$LOG_DIR"

echo "[1/6] 绑定 Gateway 工作目录到当前项目 & 提高 max_output_tokens & 调整 delegation timeout..."
hermes config set terminal.cwd "$PROJECT_ROOT"
hermes config set model.max_tokens 32768
hermes config set providers.zai.request_timeout_seconds 300
hermes config set delegation.child_timeout_seconds 1200
hermes config set delegation.max_concurrent_children 3
hermes config set credential_pool_strategies.zai round_robin

echo "[2/6] 挂载项目级 Skills 到 Hermes..."
"$HERMES_PY" - "$PROJECT_ROOT/skills" <<'PY'
import sys, json, pathlib, yaml
target = sys.argv[1]
cfg_path = pathlib.Path.home()/'.hermes/config.yaml'
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
print(f'[skills] external_dirs => {new_list}')
PY

echo "[3/6] 安装项目 Shell Hooks..."
"$HERMES_PY" - <<'PY'
import pathlib, yaml

cfg_path = pathlib.Path.home() / ".hermes/config.yaml"
cfg = yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}
cfg = cfg or {}

hooks = cfg.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

# 注册 hooks：与 patent 项目实际 hooks 文件对应
# Patent 项目 hooks 在项目根目录 hooks/ 下（不在 .claude/hooks/）

# PreToolUse hook: subagent-context-injector.sh (matcher: Task)
pre_bucket = hooks.get("pre_tool_call")
if not isinstance(pre_bucket, list):
    pre_bucket = []
    hooks["pre_tool_call"] = pre_bucket

# PostToolUse hook: task-validator.sh (matcher: Task)
# 注意：task-validator 和 subagent-context-injector 是 PreToolUse，
# 但 Hermes 的 hook 注册机制使用 post_tool_call / pre_tool_call 等字段

cfg["hooks"] = hooks

if cfg.get("hooks_auto_accept") is not True:
    cfg["hooks_auto_accept"] = True
    print("[hooks] hooks_auto_accept -> true")

cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))
print('[hooks] patent project hooks 配置已写入')
PY

echo "[4/6] Patch Hermes: 启用 parallel_tool_calls + 禁用 Anthropic SDK 内部重试..."
"$HERMES_PY" - <<'PY'
import pathlib, sys

# Patch 1: parallel_tool_calls in chat_completions.py
target = pathlib.Path.home() / '.hermes/hermes-agent/agent/transports/chat_completions.py'
if target.exists():
    src = target.read_text()
    marker = 'api_kwargs["parallel_tool_calls"] = True'
    if marker in src:
        print("[patch] parallel_tool_calls=True 已存在，跳过")
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
            target.write_text(patched)
            print(f"[patch] 成功在 {count} 处插入 parallel_tool_calls=True")
        else:
            print("[patch] 未找到匹配的插入点（可能已被修改或 Hermes 版本变更），跳过")
else:
    print(f"[patch] 文件不存在: {target}，跳过")

# Patch 2: disable Anthropic SDK internal retries
target2 = pathlib.Path.home() / '.hermes/hermes-agent/agent/anthropic_adapter.py'
if target2.exists():
    src2 = target2.read_text()
    marker2 = 'max_retries=0  # patched: disable SDK internal retries'
    if marker2 in src2:
        print("[patch] anthropic max_retries=0 已存在，跳过")
    else:
        old = '    return _anthropic_sdk.Anthropic(**kwargs)'
        new = '    kwargs["max_retries"] = 0  # patched: disable SDK internal retries\n    return _anthropic_sdk.Anthropic(**kwargs)'
        if old in src2:
            target2.write_text(src2.replace(old, new, 1))
            print("[patch] anthropic_adapter.py: max_retries=0 已插入，禁用 SDK 内部重试")
        else:
            print("[patch] 未找到插入点（可能已被修改），跳过")
else:
    print(f"[patch] 文件不存在: {target2}，跳过")
PY

echo "[5/6] 启动 Hermes Gateway + Dashboard..."
hermes gateway start

DASHBOARD_LOG="$LOG_DIR/dashboard.log"
dashboard_status="$(hermes dashboard --status 2>/dev/null || true)"
if printf "%s" "$dashboard_status" | rg -qi "No hermes dashboard processes running"; then
  hermes dashboard --no-open >"$DASHBOARD_LOG" 2>&1 &
  for _ in 1 2 3 4 5; do
    sleep 1
    if hermes dashboard --status 2>/dev/null | rg -qi "running|pid|9119"; then
      echo "Dashboard 已启动。"
      break
    fi
  done
elif printf "%s" "$dashboard_status" | rg -qi "running|pid|9119"; then
  echo "Dashboard 已在运行，跳过重复启动。"
else
  hermes dashboard --no-open >"$DASHBOARD_LOG" 2>&1 &
  sleep 3
  echo "Dashboard 状态不明确，已尝试启动。"
fi

echo "当前状态："
hermes gateway status || true
hermes dashboard --status || true

if hermes dashboard --status 2>/dev/null | rg -qi "running|pid|9119"; then
  if command -v open >/dev/null 2>&1; then
    open "http://127.0.0.1:9119/" || true
  fi
else
  echo "Dashboard 似乎未成功启动，请查看日志：$DASHBOARD_LOG"
fi

echo "[6/6] 启动 Output 文件服务（http://127.0.0.1:9131，仅暴露 output/）..."
mkdir -p "$PROJECT_ROOT/output"
pkill -f "http.server 9131" 2>/dev/null || true
python3 -m http.server 9131 --directory "$PROJECT_ROOT/output" >"$LOG_DIR/output-server.log" 2>&1 &
echo "Output 文件服务已启动：http://127.0.0.1:9131"

echo "启动完成。"