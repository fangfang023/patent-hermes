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
        or _env("LAOZHANG_OPENAI_API_KEY")
        or _env("MINIMAX_CN_API_KEY")
    )

    if model_default:
        model["default"] = model_default
    if model_provider:
        model["provider"] = model_provider
    # base_url: 始终写入（可能为空，需清除旧值）
    if model_base_url:
        model["base_url"] = model_base_url
    elif "base_url" in model:
        del model["base_url"]
    model["max_tokens"] = 32768
    if model_api_key:
        model["api_key"] = model_api_key

    # 调优参数
    cfg.setdefault("delegation", {})["child_timeout_seconds"] = 1200
    cfg["delegation"]["max_concurrent_children"] = 3
    cfg["terminal"] = {"cwd": project_dir}
    # zai provider 已移除（余额不足，不再使用 Hermes 内置 zai 路由）

    # ── auxiliary vision 配置 ──
    # 当主模型 provider 为自定义 provider（如 laozhang-openai）时，
    # Hermes 无法从 models.dev 查询其 vision 能力，导致 image_routing
    # 回退到 "text" 模式（依赖 vision_analyze 工具）。
    # 显式配置 auxiliary.vision 让 vision_analyze 使用同一个 provider，
    # 确保图片/PDF 能被正确识别。
    aux = cfg.setdefault("auxiliary", {})
    vis = aux.setdefault("vision", {})
    if model_provider and model_base_url and model_api_key:
        vis["provider"] = model_provider
        vis["base_url"] = model_base_url
        vis["api_key"] = model_api_key
        vis["model"] = model_default or "gpt-4.1"
        vis["timeout"] = 120
        vis["download_timeout"] = 30
    # 如果主模型没有配置（如首次运行），保持 auto 不动

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
    print(f"  auxiliary.vision.provider = {vis.get('provider', 'auto')}")
    print(f"  auxiliary.vision.model = {vis.get('model', '(auto)')}")


# ──────────────────────────── 步骤 2: 同步飞书变量到 .env ────────────────────────────

# 需要同步到 ~/.hermes/.env 的变量列表
SYNC_VARS = [
    "HERMES_MODEL_API_KEY",
    "MINIMAX_CN_API_KEY",
    "MINIMAX_CN_BASE_URL",
    "OPENAI_API_KEY",
    # OpenRouter · Kimi（OpenAI 协议）
    "OPENROUTER_KIMI_BASE_URL",
    "OPENROUTER_KIMI_API_KEY",
    "OPENROUTER_KIMI_MODEL",
    # 老张 API · GPT（OpenAI 协议）
    "LAOZHANG_OPENAI_BASE_URL",
    "LAOZHANG_OPENAI_API_KEY",
    "LAOZHANG_OPENAI_MODEL",
    # 飞书
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

    # 从环境变量更新（仅在环境变量有值时覆盖，避免空值清掉已有凭据）
    synced = {}
    for var in SYNC_VARS:
        val = _env(var)
        if val:
            merged[var] = val
            synced[var] = val
        elif var not in merged:
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


# ──────────────────────────── 步骤 6: 注册自定义 Provider + Fallback ────────────────────────────

# 自定义 provider 定义
#
# Hermes 合法的 provider 配置键 (config.yaml -> providers.<id>.xxx):
#   base_url, api_key, key_env, api_mode, name, model, default_model, models,
#   context_length, request_timeout_seconds, stale_timeout_seconds, rate_limit_delay
#
# api_mode 取值:
#   "chat_completions"      — OpenAI Chat Completions 协议
#   "anthropic_messages"    — Anthropic Messages 协议
#   "codex_responses"       — OpenAI Codex Responses 协议
#
# 凭据解析优先级:
#   api_key > key_env (从 ~/.hermes/.env 读取) > OPENAI_API_KEY > OPENROUTER_API_KEY
#
CUSTOM_PROVIDERS = [
    {
        "id": "openrouter-kimi",
        "base_url_env": "OPENROUTER_KIMI_BASE_URL",
        "api_key_env": "OPENROUTER_KIMI_API_KEY",
        "model_env": "OPENROUTER_KIMI_MODEL",
        "api_mode": "chat_completions",
        "name": "OpenRouter · Kimi",
    },
    {
        "id": "laozhang-openai",
        "base_url_env": "LAOZHANG_OPENAI_BASE_URL",
        "api_key_env": "LAOZHANG_OPENAI_API_KEY",
        "model_env": "LAOZHANG_OPENAI_MODEL",
        "api_mode": "chat_completions",
        "name": "老张 API · GPT",
    },
]

# 额外的 model_aliases（不属于 CUSTOM_PROVIDERS 但需要直接别名来覆盖 Hermes 自动检测）
#
# 解决的问题：
#   gpt-5.1 — Hermes 默认路由到 openai-codex（需要 OAuth），无法使用自定义 API
#

EXTRA_MODEL_ALIASES = {
    "gpt-4.1": {
        "model": "gpt-4.1",
        "provider": "laozhang-openai",
        "base_url": "https://api.laozhang.ai/v1",
    },
    "gpt-5.1": {
        "model": "gpt-5.1",
        "provider": "laozhang-openai",
        "base_url": "https://api.laozhang.ai/v1",
    },
    "kimi-k2.6": {
        "model": "kimi-k2.6",
        "provider": "openrouter-kimi",
        "base_url": "https://openrouter.ai/api/v1",
    },
}


def step_register_providers(cfg_path: pathlib.Path) -> None:
    """注册自定义 provider 和 fallback_providers 到 config.yaml。

    每个 provider 的 API key 通过 key_env 指向 ~/.hermes/.env 中的环境变量，
    这样 Hermes 在运行时可以正确解析凭据并路由请求。

    注意：使用完全覆盖（而非 setdefault）以确保清除旧版本残留的非法配置键。
    """
    import subprocess

    cfg = _load_config(cfg_path)
    providers = cfg.setdefault("providers", {})
    fallback_list = cfg.get("fallback_providers", [])
    if not isinstance(fallback_list, list):
        fallback_list = []

    # ── 清理已移除的 provider 残留 ──
    active_ids = {prov["id"] for prov in CUSTOM_PROVIDERS}
    # 本项目历史注册过的 provider id 列表（用于清理旧版本残留）
    project_provider_ids = {"zhipu-guanghua", "laozhang", "laozhang-openai", "openrouter-kimi"}
    removed_ids = set()
    for pid in list(providers.keys()):
        # 只清理本项目注册过的 provider，不碰 Hermes 内置或其他 provider
        if pid not in project_provider_ids:
            continue
        if pid not in active_ids:
            del providers[pid]
            removed_ids.add(pid)
    # 清理 fallback_providers 中的残留
    fallback_list = [
        fp for fp in fallback_list
        if fp.get("provider") not in removed_ids
    ]
    # 清理 model_aliases 中残留的模型名（属于已移除或不存在于 CUSTOM_PROVIDERS 的 provider）
    aliases = cfg.get("model_aliases", {})
    if isinstance(aliases, dict):
        aliases = {
            k: v for k, v in aliases.items()
            if v.get("provider") not in removed_ids
            and v.get("provider") in active_ids
        }
    # 清理 credential store 中残留的凭据
    for pid in removed_ids:
        try:
            subprocess.run(
                ["hermes", "auth", "remove", pid, "--yes"],
                capture_output=True, text=True, timeout=10,
            )
            print(f"  [cleanup] 已移除旧 provider '{pid}' 的凭据")
        except FileNotFoundError:
            pass
        except subprocess.TimeoutExpired:
            pass
    if removed_ids:
        print(f"  [cleanup] 已从 config.yaml 清理旧 provider: {removed_ids}")

    registered = []
    for prov in CUSTOM_PROVIDERS:
        base_url = _env(prov["base_url_env"])
        api_key = _env(prov["api_key_env"])
        model_name = _env(prov["model_env"])

        if not api_key:
            print(f"  [providers] {prov['id']}: API key 未配置（{prov['api_key_env']} 为空），跳过")
            continue

        # 完全覆盖 provider 配置（清除旧版本可能残留的 protocol 等非法键）
        providers[prov["id"]] = {
            "base_url": base_url,
            "key_env": prov["api_key_env"],      # 指向 ~/.hermes/.env 中的变量名
            "api_mode": prov["api_mode"],
            "name": prov["name"],
            "default_model": model_name,
            "request_timeout_seconds": 300,
        }

        # 添加到 fallback_providers（避免重复）
        if model_name:
            exists = any(
                fp.get("provider") == prov["id"] and fp.get("model") == model_name
                for fp in fallback_list
            )
            if not exists:
                fallback_entry = {"provider": prov["id"], "model": model_name}
                fallback_list.append(fallback_entry)

        registered.append(prov["id"])
        print(f"  [providers] {prov['id']}: base_url={base_url}, model={model_name}, api_mode={prov['api_mode']}")

        # 自动注册 credential（hermes auth add），使 /model 命令可以发现该 provider
        try:
            result = subprocess.run(
                ["hermes", "auth", "add", prov["id"],
                 "--type", "api-key",
                 "--api-key", api_key,
                 "--label", f"patent-{prov['id']}"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                print(f"  [credentials] {prov['id']}: 已注册到 credential store")
            else:
                print(f"  [credentials] {prov['id']}: {result.stdout.strip() or result.stderr.strip()}")
        except FileNotFoundError:
            print("  [credentials] hermes CLI 未找到，跳过")
        except subprocess.TimeoutExpired:
            print(f"  [credentials] {prov['id']}: 注册超时，跳过")

    # 清理 fallback_providers 中不属于当前 active_models 的旧条目
    active_models_for_fallback = {
        (_env(prov["model_env"]), prov["id"])
        for prov in CUSTOM_PROVIDERS if _env(prov["model_env"])
    }
    fallback_list = [
        fp for fp in fallback_list
        if (fp.get("model"), fp.get("provider")) in active_models_for_fallback
        or fp.get("provider") not in {p["id"] for p in CUSTOM_PROVIDERS}
    ]

    cfg["fallback_providers"] = fallback_list

    # ── model_aliases：为每个自定义 provider 的模型创建直接别名 ──
    #
    # 解决的问题：
    #   Hermes 的 /model 命令在做模型名自动检测时，会按静态目录匹配 provider。
    #   例如 gpt-5.1 在 openai-codex 的 DEFAULT_CODEX_MODELS 中，导致被路由到
    #   需要 OAuth 的 OpenAI Codex provider 而非自定义的 laozhang-openai。
    #
    #   即使显式指定 --provider laozhang-openai，credential pool 按 base_url
    #   匹配时也可能返回同一 base_url 下其他 provider 的错误凭据。
    #
    #   model_aliases 是 Hermes model_switch.py 的最高优先级路径（direct alias），
    #   在所有自动检测之前匹配，直接指定 provider + base_url，跳过 pool 匹配。
    #
    # aliases 已在上方清理逻辑中过滤了被移除的 provider，直接复用
    # 先清理同一 provider 下旧的模型 alias（避免更换模型后残留旧条目）
    active_models = set()
    for prov in CUSTOM_PROVIDERS:
        model_name = _env(prov["model_env"])
        if model_name and prov["id"] in registered:
            active_models.add(model_name)
    aliases = {
        k: v for k, v in aliases.items()
        if k in active_models
    }
    for prov in CUSTOM_PROVIDERS:
        model_name = _env(prov["model_env"])
        base_url = _env(prov["base_url_env"])
        if model_name and prov["id"] in registered:
            aliases[model_name] = {
                "model": model_name,
                "provider": prov["id"],
                "base_url": base_url,
            }

    # 合入额外别名（内置 provider 的模型名需要覆盖自动检测）
    aliases.update(EXTRA_MODEL_ALIASES)

    cfg["model_aliases"] = aliases
    _save_config(cfg, cfg_path)

    print(f"[providers] 已注册 {len(registered)} 个自定义 provider: {registered}")
    print(f"[providers] fallback_providers => {fallback_list}")
    print(f"[providers] model_aliases => {list(aliases.keys())}")


# ──────────────────────────── 步骤 7: 安装 i18n 翻译文件 ────────────────────────────

def step_install_locales(project_dir: str) -> None:
    """将项目自带的 locales 翻译文件复制到 Hermes site-packages 中。

    hermes-agent 通过 pip 安装时可能不包含 locales/ 翻译目录，
    导致 gateway 的 /model 等命令回复显示原始 i18n 键名而非可读文本。
    此步骤将项目 docker/locales/ 下的 yaml 文件复制到正确的位置。
    """
    # 定位 Hermes agent 的 site-packages 路径
    try:
        import agent.i18n as _i18n
        locales_target = _i18n._locales_dir()
    except (ImportError, AttributeError):
        print("[locales] 无法定位 Hermes locales 目录，跳过")
        return

    # 项目自带的 locales 目录
    project_locales = pathlib.Path(project_dir) / "docker" / "locales"
    if not project_locales.is_dir():
        print(f"[locales] 项目 locales 目录不存在 ({project_locales})，跳过")
        return

    yaml_files = list(project_locales.glob("*.yaml"))
    if not yaml_files:
        print("[locales] 项目 locales 目录中没有 yaml 文件，跳过")
        return

    locales_target.mkdir(parents=True, exist_ok=True)

    copied = []
    for src in yaml_files:
        dst = locales_target / src.name
        dst.write_text(src.read_text())
        copied.append(src.name)

    print(f"[locales] 已安装 {len(copied)} 个翻译文件到 {locales_target}")
    print(f"  files: {copied}")


# ──────────────────────────── 步骤 8: Patch Hermes ────────────────────────────

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

    step_register_providers(cfg_path)
    print()

    step_install_locales(project_dir)
    print()

    if not args.skip_patch:
        step_patch_hermes(home_dir)
    else:
        print("[patch] 跳过（--skip-patch）")
    print()

    print("hermes_init.py 完成。")


if __name__ == "__main__":
    main()
