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

## 端口说明

| 端口 | 宿主机默认 | 说明 |
|------|-----------|------|
| Dashboard | 9130 | Hermes Dashboard |
| Gateway | 8790 | Gateway / 飞书 Webhook |
| Output Server | 9131 | 输出文件 HTTP 服务 |

端口已避开 courseware 项目（9120/8780/9121），可同时运行。

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

## 配置说明

- 模型：MiniMax-M2.7 / minimax-cn provider
- 飞书：独立机器人（与 courseware 项目不是同一个）
- 详见 [docker/.env.example](docker/.env.example)