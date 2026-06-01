# Patent Hermes Agent

专利智能生成系统 —— 基于 Hermes Agent 架构的专利文档自动化生成平台。

## 项目概述

Patent Hermes Agent 将用户输入（技术创意、交底素材、审查意见等）转换为一整套专利文档，包括：

- 技术交底书（生成 / 完善 / 多轮质疑循环）
- 权利要求书 + 说明书 + 全套专利申请文件
- 审查意见答复 + 驳回复审分析
- 批量创意 → 多篇专利自动生成
- 产品方案 / 技术方案 / 运营方案 / IP 保护策略
- 各类技术文档与学术论文

## 项目结构

```
patent-hermes/
├── AGENTS.md              # Hermes 注入的核心规则（路由、编排、约束）
├── CLAUDE.md              # Claude Code 扩展上下文（Agent/Skill 列表、路由规则）
├── agents/                # Agent 定义（编排器、质疑器、审核器）
├── skills/                # Skill 定义（文档生成技能）
├── knowledge/             # 知识库（法律参考、审核标准、审查指南）
│   ├── guidelines/        # 专利审查指南
│   ├── references/        # 权利要求规则、分案标准等
│   ├── review-standards/  # 文档审核标准
│   └── workflows/         # 端到端流程定义
├── hooks/                 # Shell hooks（上下文注入、任务验证）
├── commands/              # Claude Code 自定义命令
├── scripts/               # 启动 / 停止 / 配置脚本
│   ├── start.sh           # 本地启动
│   ├── stop.sh            # 本地停止
│   └── lib/               # 共享工具
├── docker/                # Docker 部署
│   ├── Dockerfile         # 镜像定义
│   ├── docker-compose.yml # 容器编排
│   ├── start.sh           # 容器启动脚本
│   └── .env.example       # 环境变量模板
├── workflows/             # 端到端流程定义
├── output/                # 最终产物目录
└── docs/                  # 项目文档
```

## 快速启动

### 本地启动

```bash
# 1. 启动 Hermes（自动配置、挂载 Skills、安装 Hooks）
./scripts/start.sh

# 2. 终端触发任务
hermes -z "帮我生成一份技术交底书，创意是关于XXX"
```

### Docker 部署

```bash
# 1. 填写环境变量
cd docker && cp .env.example .env
# 编辑 .env，填入 API Key 和飞书机器人配置

# 2. 启动
./docker/start.sh
```

详见 [docker/README.md](docker/README.md)。

## Agent 体系

| Agent | 用途 |
|-------|------|
| disclosure-agent | 交底书生成/完善/质疑循环 |
| patent-drafting-agent | 专利撰写管线 |
| prosecution-agent | 审查答复管线 |
| batch-patent-generator | 批量前置：论文+创意挖掘 |
| single-creative-generator | 单创意全套生成 |
| patent-challenger-agent | 对抗式质疑 |
| document-reviewer-agent | 结构化质量审核 |

详见 [AGENTS.md](AGENTS.md) 和 [agents/](agents/)。

## Docker 部署详解

### 端口占用

容器启动后会占用宿主机端口，需要确保这些端口在本机上没有被其他服务使用。端口在 `docker/.env` 中配置：

| 宿主机端口变量 | 当前值 | 用途 |
|--------------|--------|------|
| `DASHBOARD_HOST_PORT` | 9105 | Hermes Dashboard Web 界面 |
| `GATEWAY_HOST_PORT` | 9106 | Gateway（飞书 Webhook 入口） |
| `OUTPUT_HOST_PORT` | 9107 | 产出文件下载服务 |

> **多项目共存**：同一台机器上运行多个 Docker 项目时，只需修改 `docker/.env` 中的 `_HOST_PORT` 值，确保宿主机端口互不冲突即可。容器内端口（`_CONTAINER_PORT`）彼此隔离，不会冲突，无需修改。

### 卷挂载

| 挂载类型 | 宿主机路径 | 容器路径 | 用途 |
|----------|-----------|---------|------|
| Bind mount | 项目根目录 `..` | `/app/patent-hermes-agent` | 项目源码（代码修改实时生效） |
| Named volume | `patent-hermes-home` | `/root/.hermes` | Hermes 状态持久化（config.yaml / sessions / state.db / auth.json） |

> **多项目共存**：Named volume 名为 `patent-hermes-home`（在 `docker-compose.yml` 中显式指定）。如果同一台机器上有其他项目也叫这个名字，会共享同一个 volume 导致配置互相覆盖。多项目部署时需修改 volume 名。

### 容器名称

- Compose project name: `patent-hermes`
- 容器名: `patent-hermes-agent`
- 镜像名: `patent-hermes-agent:latest`

> 同一机器上部署多个项目时，需确保容器名和镜像名不重复。

### 访问地址

启动成功后，浏览器访问：

- Dashboard: `http://<服务器IP>:${DASHBOARD_HOST_PORT}/`
- 文件下载: `http://<服务器IP>:${OUTPUT_HOST_PORT}/`


## 环境变量配置

所有配置集中在 `docker/.env` 中，首次部署从模板创建：

```bash
cd docker && cp .env.example .env
```

### 必填项

| 变量 | 说明 |
|------|------|
| `HERMES_MODEL_API_KEY` | 主模型 API Key（Moonshot / 老张 API 等） |
| `MOONSHOT_KIMI_API_KEY` | Moonshot API Key（使用 Kimi 模型时必填） |
| `MINIMAX_CN_API_KEY` | MiniMax API Key（备用模型） |
| `FEISHU_APP_ID` | 飞书机器人 App ID（需要飞书接入时填写） |
| `FEISHU_APP_SECRET` | 飞书机器人 App Secret |

### 主模型切换

通过 `HERMES_MODEL_DEFAULT` / `HERMES_MODEL_PROVIDER` / `HERMES_MODEL_BASE_URL` 三个变量控制：

| 模型 | `HERMES_MODEL_DEFAULT` | `HERMES_MODEL_PROVIDER` | `HERMES_MODEL_BASE_URL` |切换命令 |
|------|----------------------|------------------------|------------------------|-------|
| Kimi-K2.6 | `kimi-k2.6` | `moonshot-kimi` | `https://api.moonshot.cn/anthropic` | /model kimi-k2.6|
| GPT-4.1 | `gpt-4.1` | `laozhang-openai` | `https://api.laozhang.ai/v1` |/model gpt-4.1|
| MiniMax-M2.7 | `MiniMax-M2.7` | `minimax-cn` | `https://api.minimaxi.com/anthropic` |/model MiniMax-M2.7|

> 完整变量说明见 [docker/.env.example](docker/.env.example)，每个变量都有注释。