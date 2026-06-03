# Patent Hermes Agent — Claude Code 开发指引

> 本文件由 Claude Code 在每次会话开始时自动注入。
> **运行时的编排规则、路由分流、强约束等请读 `AGENTS.md`**——那里是 Hermes 执行任务时遵守的完整规则。

## 项目概述

专利智能生成系统，基于 Hermes Agent 架构。将用户输入（技术创意、交底素材、审查意见等）转换为一整套专利文档。

## 目录结构

```
patent-hermes/
├── AGENTS.md              # ⭐ Hermes 运行时规则（路由、编排、约束）— 修改编排逻辑时读这里
├── agents/                # Agent 定义文件（每个 .md 一个 agent）
│   ├── disclosure-agent.md          # 交底书编排器
│   ├── patent-drafting-agent.md     # 专利撰写编排器
│   ├── prosecution-agent.md         # 审查答复编排器
│   ├── batch-patent-generator.md    # 批量前置编排器
│   ├── single-creative-generator.md # 单创意生成编排器
│   ├── patent-challenger-agent.md   # 质疑编排器
│   └── document-reviewer-agent.md   # 审核编排器
├── skills/                # Skill 定义目录（每个子目录一个 skill，含 SKILL.md）
│   ├── tech-disclosure/              # 技术交底书
│   ├── disclosure-challenger/        # 专利质疑
│   ├── oa-response/                  # 答复审查意见
│   ├── ...（详见 skills/ 目录）
├── knowledge/             # 知识库
│   ├── guidelines/        # 审查指南（专利审查指南 2023、AI 专利审查问题等）
│   ├── references/        # 参考规则（权利要求撰写规则、分案标准、优先审查关键词等）
│   ├── review-standards/  # 审核标准（按文档类型分类）
│   └── workflows/         # 端到端流程定义
├── hooks/                 # Hermes/Claude Code hooks（已移除 Claude Code hooks，Hermes hooks 未注册）
├── commands/              # Claude Code 自定义命令
├── scripts/               # 启动 / 停止 / 配置脚本
├── docker/                # Docker 部署定义
├── workflows/             # 端到端流程定义（空目录，待补充）
└── output/                # 最终产物目录
```

## 开发时关键文件速查

| 你要做什么 | 先读哪个文件 |
|-----------|------------|
| 理解项目编排规则和约束 | `AGENTS.md` |
| 修改某个 Agent 的行为 | `agents/{agent-name}.md` |
| 修改某个 Skill 的生成逻辑 | `skills/{skill-name}/SKILL.md` |
| 查看审核标准 | `knowledge/review-standards/{类型}/` |
| 查看审查指南 | `knowledge/guidelines/` |
| 查看权利要求规则 | `knowledge/references/claims-drafting-rules.md` |
| 查看分案标准 | `knowledge/references/divisional-standards.md` |
| 修改部署配置 | `docker/.env.example` → `docker/.env` |
| 修改 Hermes 启动逻辑 | `scripts/start.sh` |

## 运行与部署

### 本地启动
```bash
cd scripts && cp .env.example .env   # 配置端口（首次）
./scripts/start.sh    # 启动 Hermes + Dashboard + Gateway + Output Server
./scripts/stop.sh     # 停止所有服务
```

### Docker 部署
```bash
cd docker && cp .env.example .env   # 填入 API Key 和飞书机器人配置
./docker/start.sh                   # 构建镜像并启动容器
```

### 端口配置
所有端口均在 `scripts/.env`（本地）或 `docker/.env`（Docker）中集中定义，脚本和 compose 文件中不硬编码任何端口号。

| 服务 | 本地变量 | Docker 容器内变量 | Docker 宿主机映射变量 |
|------|---------|-----------------|---------------------|
| Dashboard | `DASHBOARD_PORT` | `DASHBOARD_CONTAINER_PORT` | `DASHBOARD_HOST_PORT` |
| Gateway | `GATEWAY_PORT`（本地无效，内置默认 8765） | `GATEWAY_CONTAINER_PORT` | `GATEWAY_HOST_PORT` |
| Output Server | `OUTPUT_PORT` | `OUTPUT_CONTAINER_PORT` | `OUTPUT_HOST_PORT` |

### 测试运行
```bash
# 本地终端
hermes -z "帮我生成一份技术交底书，创意是关于XXX"

# Dashboard 界面
浏览器打开 http://192.168.8.234:${DASHBOARD_PORT}/（端口由 scripts/.env 中的 DASHBOARD_PORT 控制）
```

## Agent 调用方式

使用 Claude Code 开发时，调用 Agent 的格式：

```python
Task(subagent_type="agent-name", description="3-5词描述", prompt="完整任务指令")
```

可用的 `subagent_type` 值：
- `disclosure-agent` — 交底书相关
- `patent-drafting-agent` — 专利撰写相关
- `prosecution-agent` — 审查答复相关
- `batch-patent-generator` — 批量专利前置
- `single-creative-generator` — 单创意生成
- `patent-challenger-agent` — 质疑
- `document-reviewer-agent` — 审核

**路由规则详见 `AGENTS.md` §3。**

## Skill 调用方式

```python
Skill(skill="skill-name")
```

所有 skill 名称与 `skills/` 目录下的子目录名一致（去掉前缀 `patent-` / `technical-` / `paper-` 等也可以用简称）。

## 文档输出

- 输出目录：`output/` 或 `generated_docs/`
- 命名格式：`[文档类型]_[创意简述]_[时间戳].md`
- 批量专利目录结构：`output/创意_{timestamp}/创意N/` 下 7 个文件
