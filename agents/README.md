# Technical Expert Agents Directory
#
# This directory contains specialized expert agents for technical consultation
# Each agent is defined as a markdown file following the standard format:
#
# ---
# name: agent-name
# description: Agent description
# tools: tool1, tool2, tool3
# skills:
#   - skill-name-1
#   - skill-name-2
# maxTurns: 30
# effort: high
# color: cyan
# ---
#
# Agent system prompt and instructions
#
# Key design principles:
# - skills field: preloads Skill content into Agent context at startup
# - maxTurns: prevents runaway execution
# - effort: high for document generation/review tasks
# - color: visual distinction in status line
# - Agent cannot spawn other Agents (Subagent nesting not supported)

---

## Available Agents

### 领域编排 Agent（处理复杂多步骤管线）

| Agent | Description | Skills Preloaded | When to Use |
|--------|-------------|------------------|-------------|
| `disclosure-agent` | 交底书领域复杂工作流编排 | patent-tech-disclosure, patent-challenger, utils-document-reviewer, utils-innovation-checker | 交底书生成/完善 + 质疑循环 |
| `patent-drafting-agent` | 专利撰写领域复杂管线编排 | patent-claims-writing, patent-patent-writing, patent-tech-disclosure, patent-challenger, utils-document-reviewer, utils-innovation-checker, patent-innovation-splitter, patent-divisional-analysis, patent-claims-review-and-amendment, patent-law-reference | 全套专利、权利要求书、说明书、母案分案、创新评估+撰写 |
| `prosecution-agent` | 审查答复领域复杂管线编排 | patent-office-action-response, patent-claims-review-and-amendment, patent-reexamination-response, patent-law-reference | OA答复、驳回复审、申请人疑问分析 |

### 批量专利 Agent

| Agent | Description | Skills Preloaded | When to Use |
|--------|-------------|------------------|-------------|
| `batch-patent-generator` | 批量前置阶段编排器 | paper-engineering-paper, paper-science-paper, paper-economy-paper | 批量创意→论文→创意挖掘 |
| `single-creative-generator` | 单创意专利+方案生成器 | patent-patent-writing, patent-product-plan, technical-tech-solution, patent-operation-plan, patent-ip-strategy | 单个创意全套生成 |

### 质疑与审核 Agent

| Agent | Description | Skills Preloaded | When to Use |
|--------|-------------|------------------|-------------|
| `patent-challenger-agent` | 专利质疑者 | patent-challenger | 对抗式质疑交底书或权利要求书 |
| `document-reviewer-agent` | 文档审核器 | utils-document-reviewer, utils-innovation-checker | 文档质量打分与评审 |

---

## Architecture: 按领域拆分 + 按复杂度分流

```
CLAUDE.md（轻量路由）
  │
  ├── 简单任务 → 主 Claude + Skill 直出
  │     单文档生成（快速）、简单修改、咨询讨论、单次审核
  │
  ├── 交底书领域 → disclosure-agent
  │     生成/完善 + 质疑循环
  │
  ├── 专利撰写领域 → patent-drafting-agent
  │     L1→L2管线、母案分案、创新评估+撰写、权利要求+说明书联动
  │
  ├── 审查答复领域 → prosecution-agent
  │     OA答复、驳回复审、申请人疑问分析
  │
  └── 批量 → batch-patent-generator → single-creative-generator
```

**设计原则**：
- **Skill 负责知识**：审核标准、质疑规则、输出格式等定义在 Skill 的 references/ 和 SKILL.md 中
- **Agent 负责编排**：流程控制、调用顺序、循环逻辑写在 Agent prompt 中
- **skills 字段是桥梁**：Agent 启动时自动加载 Skill 内容到上下文，无需运行时查找
- **默认走 Agent 保障质量**：用户不需要知道"质疑"等概念，系统自动保障
- **子 Agent 不能嵌套**：Agent 内部通过预加载 Skill 知识自行执行质疑/审核，不调用其他 Agent
