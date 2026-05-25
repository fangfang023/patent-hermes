#!/usr/bin/env python3
"""
Patent Hermes Agent · 共享初始化模块

本地和 Docker 部署共用此脚本完成 Hermes 的配置初始化。
所有配置值从环境变量读取（不 source 任何 .env 文件），
路径通过 --project-dir / --home-dir 参数适配本地/容器环境。

用法：
  本地：  python3 scripts/hermes_init.py --project-dir /path/to/patent-hermes
  Docker：docker exec ... python3 /app/patent-hermes-agent/scripts/hermes_init.py \
            --project-dir /app/patent-hermes-agent --home-dir /root/.hermes
"""

import argparse
import json
import os
import pathlib
import sys

import yaml


# ──────────────────────────── 工具 ────────────────────────────

def _env(name: str, default: str = "") -> str:
    """从环境变量读取值。"""
    return os.getenv(name, default)


def _load_config(cfg_path: pathlib.Path) -> dict:
    """加载 YAML 配置，空文件返回空 dict。"""
    if cfg_path.exists():
        text = cfg_path.read_text()
        if text.strip():
            return yaml.safe_load(text) or {}
    return {}


def _save_config(cfg: dict, cfg_path: pathlib.Path) -> None:
    """保存 YAML 配置。"""
    cfg_path.parent.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))


def _mask(val: str, show: int = 20) -> str:
    """遮盖敏感值，只显示前 N 个字符。"""
    if not val:
        return "(empty)"
    return f"{val[:show]}...({len(val)} chars)"


# ──────────────────────────── 步骤 1: 模型 + 调优参数 ────────────────────────────

def step_config_model(cfg_path: pathlib.Path, project_dir: str) -> None:
    """同步模型配置和调优参数到 config.yaml。"""
    cfg = _load_config(cfg_path)

    # 模型配置（从环境变量读取）
    model = cfg.setdefault("model", {})
    model_default = _env("HERMES_MODEL_DEFAULT")
    model_provider = _env("HERMES_MODEL_PROVIDER")
    model_base_url = _env("HERMES_MODEL_BASE_URL")
    model_api_key = (
        _env("HERMES_MODEL_API_KEY")
        or _env("OPENAI_API_KEY")
        or _env("KIMI_CN_API_KEY")
        or _env("MINIMAX_CN_API_KEY")
    )

    if model_default:
        model["default"] = model_default
    if model_provider:
        model["provider"] = model_provider
    if model_base_url:
        model["base_url"] = model_base_url
    model["max_tokens"] = 32768
    if model_api_key:
        model["api_key"] = model_api_key

    # 调优参数
    cfg.setdefault("delegation", {})["child_timeout_seconds"] = 1200
    cfg["delegation"]["max_concurrent_children"] = 3
    cfg["terminal"] = {"cwd": project_dir}
    cfg.setdefault("credential_pool_strategies", {})["zai"] = "round_robin"
    cfg.setdefault("providers", {}).setdefault("zai", {})["request_timeout_seconds"] = 300

    _save_config(cfg, cfg_path)

    # 验证输出
    print("[config] 模型 + 调优参数已写入 config.yaml")
    print(f"  model.default = {model.get('default', '(empty)')}")
    print(f"  model.provider = {model.get('provider', '(empty)')}")
    print(f"  model.base_url = {model.get('base_url', '(empty)')}")
    print(f"  model.api_key = {_mask(model_api_key)}")
    print(f"  model.max_tokens = {model.get('max_tokens')}")
    print(f"  delegation.child_timeout_seconds = 1200")
    print(f"  delegation.max_concurrent_children = 3")
    print(f"  terminal.cwd = {project_dir}")


# ──────────────────────────── 步骤 2: 同步飞书变量到 .env ────────────────────────────

# 需要同步到 ~/.hermes/.env 的变量列表
SYNC_VARS = [
    "HERMES_MODEL_API_KEY",
    "KIMI_CN_API_KEY",
    "KIMI_API_KEY",
    "MINIMAX_CN_API_KEY",
    "MINIMAX_CN_BASE_URL",
    "OPENAI_API_KEY",
    "FEISHU_ENABLED",
    "FEISHU_APP_ID",
    "FEISHU_APP_SECRET",
    "FEISHU_DOMAIN",
    "FEISHU_CONNECTION_MODE",
    "FEISHU_GROUP_POLICY",
    # FEISHU_HOME_CHANNEL / FEISHU_HOME_CHANNEL_THREAD_ID 不在此同步
    # 用户在飞书对话中发送 /sethome 即可自动设置
    "GATEWAY_ALLOW_ALL_USERS",
    "FEISHU_ALLOW_ALL_USERS",
    "FEISHU_ALLOWED_USERS",
]


def step_sync_env(env_path: pathlib.Path) -> None:
    """同步飞书和模型 Key 变量到 ~/.hermes/.env。"""
    # 读入已有的 ~/.hermes/.env
    merged = {}
    if env_path.exists():
        for line in env_path.read_text().strip().split("\n"):
            if "=" in line:
                k, v = line.split("=", 1)
                merged[k] = v

    # 从环境变量更新
    synced = {}
    for var in SYNC_VARS:
        val = _env(var)
        merged[var] = val
        synced[var] = val

    env_path.parent.mkdir(parents=True, exist_ok=True)
    env_path.write_text("\n".join(f"{k}={v}" for k, v in merged.items()) + "\n")

    print(f"[sync] 已同步 {len(synced)} 个变量到 ~/.hermes/.env")
    for k in sorted(synced.keys()):
        print(f"  {k} = {_mask(synced[k])}")


# ──────────────────────────── 步骤 3: 挂载 Skills ────────────────────────────

def step_mount_skills(cfg_path: pathlib.Path, project_dir: str) -> None:
    """挂载项目级 Skills 目录到 Hermes config。"""
    skills_dir = f"{project_dir}/skills"
    cfg = _load_config(cfg_path)

    sk = cfg.setdefault("skills", {})
    cur = sk.get("external_dirs")

    if isinstance(cur, str):
        try:
            parsed = json.loads(cur)
            dirs_list = parsed if isinstance(parsed, list) else [str(parsed)]
        except json.JSONDecodeError:
            dirs_list = [cur]
    elif isinstance(cur, list):
        dirs_list = list(cur)
    else:
        dirs_list = []

    if skills_dir not in dirs_list:
        dirs_list.append(skills_dir)

    # 去重
    seen = set()
    dirs_list = [x for x in dirs_list if not (x in seen or seen.add(x))]
    sk["external_dirs"] = dirs_list

    _save_config(cfg, cfg_path)
    print(f"[skills] external_dirs => {dirs_list}")


# ──────────────────────────── 步骤 4: 启用插件 ────────────────────────────

# 项目需要自动启用的插件列表
REQUIRED_PLUGINS = [
    "document-processor",  # PDF/DOCX 文档预处理（在 agent 之前提取文本和图像）
]


def step_enable_plugins(cfg_path: pathlib.Path) -> None:
    """在 config.yaml 中启用项目所需的插件（opt-in 机制）。"""
    cfg = _load_config(cfg_path)

    plugins_cfg = cfg.setdefault("plugins", {})
    enabled = plugins_cfg.get("enabled", [])
    if not isinstance(enabled, list):
        enabled = []

    added = []
    for name in REQUIRED_PLUGINS:
        if name not in enabled:
            enabled.append(name)
            added.append(name)

    plugins_cfg["enabled"] = enabled
    _save_config(cfg, cfg_path)

    if added:
        print(f"[plugins] 已启用: {added}")
    else:
        print(f"[plugins] 所有必需插件已启用 ({REQUIRED_PLUGINS})")
    print(f"[plugins] plugins.enabled = {enabled}")


# ──────────────────────────── 步骤 5: 安装 Hooks ────────────────────────────

def step_setup_hooks(cfg_path: pathlib.Path) -> None:
    """启用 hooks_auto_accept（patent 项目暂无实际 hook 脚本注册）。"""
    cfg = _load_config(cfg_path)

    hooks = cfg.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        cfg["hooks"] = hooks

    if cfg.get("hooks_auto_accept") is not True:
        cfg["hooks_auto_accept"] = True
        print("[hooks] hooks_auto_accept -> true")

    _save_config(cfg, cfg_path)
    print("[hooks] patent project hooks 配置已写入")


# ──────────────────────────── 步骤 6: Patch Hermes ────────────────────────────

def _locate_hermes_file(module_path: str, filename: str, home_dir: str) -> pathlib.Path | None:
    """定位 hermes-agent 的 Python 文件。

    优先尝试 import 动态定位（适用于 pip 安装到 site-packages 的情况），
    fallback 到 hermes-home venv 路径（适用于本地安装的情况）。
    """
    # 方式 1: 通过 import 动态定位
    try:
        parts = module_path.split(".")
        mod = __import__(module_path)
        for part in parts[1:]:
            mod = getattr(mod, part)
        target = pathlib.Path(mod.__file__)
        if target.name == filename and target.exists():
            return target
    except (ImportError, AttributeError):
        pass

    # 方式 2: hermes-home venv 下的路径（本地安装）
    target = pathlib.Path(home_dir) / f"hermes-agent/agent/{module_path.replace('.', '/')}/{filename}"
    if target.exists():
        return target

    return None


def step_patch_hermes(home_dir: str) -> None:
    """Patch Hermes: 启用 parallel_tool_calls + 禁用 Anthropic SDK 内部重试。"""
    print("[patch] 开始 patching Hermes...")

    # ---- Patch 1: parallel_tool_calls ----
    target1 = _locate_hermes_file("hermes_agent.agent.transports.chat_completions", "chat_completions.py", home_dir)

    if target1 and target1.exists():
        src = target1.read_text()
        marker = 'api_kwargs["parallel_tool_calls"] = True'
        if marker in src:
            print("  [patch] parallel_tool_calls=True 已存在，跳过")
        else:
            replacements = [
                (
                    '''            api_kwargs["tools"] = tools

        # max_tokens resolution — priority: ephemeral > user > provider default''',
                    '''            api_kwargs["tools"] = tools
            api_kwargs["parallel_tool_calls"] = True

        # max_tokens resolution — priority: ephemeral > user > provider default''',
                ),
                (
                    '''            api_kwargs["tools"] = tools

        # max_tokens resolution — priority: ephemeral > user > profile default''',
                    '''            api_kwargs["tools"] = tools
            api_kwargs["parallel_tool_calls"] = True

        # max_tokens resolution — priority: ephemeral > user > profile default''',
                ),
            ]
            patched = src
            count = 0
            for old, new in replacements:
                if old in patched:
                    patched = patched.replace(old, new, 1)
                    count += 1
            if count >= 1:
                target1.write_text(patched)
                print(f"  [patch] 成功在 {count} 处插入 parallel_tool_calls=True")
            else:
                print("  [patch] 未找到匹配的插入点（可能已被修改或 Hermes 版本变更），跳过")
    else:
        print("  [patch] chat_completions.py 未找到，跳过")

    # ---- Patch 2: disable Anthropic SDK internal retries ----
    target2 = _locate_hermes_file("hermes_agent.agent.anthropic_adapter", "anthropic_adapter.py", home_dir)

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
        print("  [patch] anthropic_adapter.py 未找到，跳过")


# ──────────────────────────── 主入口 ────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Patent Hermes Agent 初始化")
    parser.add_argument("--project-dir", required=True,
                        help="项目根目录路径（本地: /path/to/patent-hermes, 容器: /app/patent-hermes-agent）")
    parser.add_argument("--home-dir", default=None,
                        help="Hermes home 目录（默认: ~/.hermes，容器内: /root/.hermes）")
    parser.add_argument("--skip-patch", action="store_true",
                        help="跳过 Hermes patch 步骤（容器首次 pip 安装时可能不需要）")
    args = parser.parse_args()

    project_dir = args.project_dir
    home_dir = args.home_dir or str(pathlib.Path.home() / ".hermes")
    cfg_path = pathlib.Path(home_dir) / "config.yaml"
    env_path = pathlib.Path(home_dir) / ".env"

    print(f"hermes_init.py: project_dir={project_dir}, home_dir={home_dir}")
    print()

    step_config_model(cfg_path, project_dir)
    print()

    step_sync_env(env_path)
    print()

    step_mount_skills(cfg_path, project_dir)
    print()

    step_enable_plugins(cfg_path)
    print()

    step_setup_hooks(cfg_path)
    print()

    if not args.skip_patch:
        step_patch_hermes(home_dir)
    else:
        print("[patch] 跳过（--skip-patch）")
    print()

    print("hermes_init.py 完成。")


if __name__ == "__main__":
    main()