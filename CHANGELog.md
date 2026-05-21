# Patent Hermes Agent 变更日志

## 2025-05-21

### 新增文件

| 文件 | 说明 |
|------|------|
| `.gitignore` | Git 忽略规则，含 patent 项目特有项（output/、docker/.env、.logs/ 等） |
| `.dockerignore` | Docker build context 排除（.git/、output/、node_modules/ 等） |
| `docker/Dockerfile` | Python 3.11-slim 基础镜像，加入 jq（hooks 需要），项目名 patent-hermes-agent |
| `docker/docker-compose.yml` | 容器名 patent-hermes-agent，volume patent-hermes-home，端口 9130/8790/9131 |
| `docker/.env.example` | 环境变量模板：端口/模型（MiniMax-M2.7）/飞书独立机器人配置 |
| `docker/start.sh` | Docker 容器启动脚本：华为云镜像拉取、容器状态机、模型配置、服务启动 |
| `docker/README.md` | Docker 部署说明文档 |
| `scripts/start.sh` | 本地 Hermes 启动（6步：config→skills→hooks→patch→gateway/dashboard→output server），含 parallel_tool_calls 和 max_retries=0 两个 patch |
| `scripts/stop.sh` | 本地 Hermes 停止（3步：gateway→dashboard→output server） |
| `scripts/lib/detect_hermes_python.sh` | 共享工具：定位 Hermes 自带 python3（有 PyYAML） |
| `AGENTS.md` | Hermes 运行时规则——路由分流、delegate_task 调用示例、role 参数选择、强约束、异常处理 |
| `README.md` | 项目说明文档 |
| `output/.gitkeep` | 输出目录占位 |
| `workflows/` | 端到端流程定义目录（空，待补充） |

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| `AGENTS.md`（新建） | §5 从 Claude Code `Task(subagent_type=...)` 改为 Hermes `delegate_task(goal=..., context=...)` 调用方式；context 只写数据，goal 指引子代理 Read agent .md |
| `CLAUDE.md` | 从业务路由规则重写为开发指引——目录结构、速查表、部署命令、指向 AGENTS.md |
| `settings.json` | hooks 路径从 `/workspace/my-workspace/.claude/hooks/` 改为 `/Users/ff/PycharmProjects/patent/patent-hermes/hooks/` |
| `settings.local.json` | 清理旧路径引用（claude-agent-orchestrator），更新 hooks 路径，补充所有 patent Skill 权限 |
| `hooks/session-start-loader.sh` | CLAUDE_MD_FILE 从硬编码 `/workspace/.claude/CLAUDE.md` 改为 `$PROJECT_ROOT/CLAUDE.md`（动态计算） |
| `hooks/subagent-context-injector.sh` | PROJECT_ROOT 从 `$SCRIPT_DIR/../..` 改为 `$SCRIPT_DIR/..`（hooks 在项目根下而非 .claude/hooks/） |
| `hooks/task-validator.sh` | AGENT_PATTERNS 从旧项目 agent 改为专利项目 7 个 agent；默认 fallback 从 generate-docs-agent 改为 disclosure-agent |

### 删除文件

| 文件 | 说明 |
|------|------|
| `hooks/session-start-loader.sh` | Claude Code hook，Hermes 环境下不起作用 |
| `hooks/subagent-context-injector.sh` | Claude Code hook，Hermes 环境下不起作用 |
| `hooks/task-validator.sh` | Claude Code hook，Hermes 环境下不起作用 |

### 核心变更说明

#### 1. 调用方式标准化

- **之前**：Claude Code `Task(subagent_type="{agent-name}", prompt="...")` 语法
- **之后**：Hermes `delegate_task(goal="任务目标。第一步：Read agents/{name}.md...", context="数据+路径", toolsets=["terminal","file"], role="orchestrator|leaf")` 语法
- **核心原则**：context 只写数据（用户输入、文件路径、参数），不写编排指令模板；子代理自己 Read agent .md 获取编排指令

#### 2. agents 目录性质澄清

- **之前**：当作 Hermes 的"Agent 定义文件注册机制"
- **之后**：澄清为"编排指令模板库"——Hermes 没有原生的 Agent 注册机制，agents/*.md 是子代理通过 Read 动态加载的指令文件

#### 3. Hermes 源码 Patch

- `chat_completions.py`：插入 `api_kwargs["parallel_tool_calls"] = True`，允许 LLM 一次回复发起多个 tool call
- `anthropic_adapter.py`：插入 `kwargs["max_retries"] = 0`，禁用 Anthropic SDK 内部重试，让重试由 Hermes 自己的 delegation timeout 体系控制

#### 4. 飞书独立配置

patent 项目使用独立的飞书机器人，在 docker/.env.example 中单独配置 FEISHU_APP_ID / FEISHU_APP_SECRET 等。

### 未修改的目录

以下目录内容未做任何修改：
- `agents/`（7 个 agent .md 定义文件）
- `commands/`（generate-docs.md、gitcommit.md）
- `knowledge/`（guidelines/references/review-standards/workflows）
- `skills/`（所有 SKILL.md 及其 references/examples/assets/scripts）