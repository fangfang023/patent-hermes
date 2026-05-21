# /generate-docs

智能文档生成命令 - 快捷调用 `generate-docs-agent` 生成技术方案、专利文档、学术论文等。

---

## 架构说明

本命令采用 **Command → Agent** 架构：
```
用户 → /generate-docs (Command)
           ↓
       Command 使用 Task 工具
           ↓
       generate-docs-agent (独立会话)
           ↓
       Agent 按六节点依赖关系执行
           ↓
       调用 Skills 完成任务
           ↓
       返回结果展示给用户
```

## 自动加载项目上下文
@/CLAUDE.md
@/docs/ai-context/project-structure.md

---

## 执行流程

使用 Task 工具调用 `generate-docs-agent`：

### 调用参数
```
subagent_type: generate-docs-agent
prompt: [用户输入]
description: 文档生成工作流
```

### 等待完成
Agent 在独立会话中执行以下操作：
1. 分析用户输入，确定起始节点（1-5）
2. 理解用户意图，确定目标节点（2-6）
3. 输出执行计划
4. 按顺序执行每个节点
5. 执行质疑环节（技术交底书）
6. 执行质量审核
7. 输出结果汇总

### 结果展示
Agent 完成后，将其返回的结果直接展示给用户。

---

## 快速开始

```bash
# 从创意生成技术交底书（最常用）
/generate-docs 我有一个基于深度学习的智能图像识别系统的创意

# 生成完整专利文档链（技术方案→交底书→权利要求书）
/generate-docs 生成完整专利申请文档：AI绿植健康管家SaaS

# 批量处理多个创意
/generate-docs 为以下创意分别生成交底书：
1. AI绿植健康管家SaaS
2. 跨境电商差评预警工具
```

## 输出目录

生成的文档默认保存在：`./generated_docs/[timestamp]/`

## 详细说明

- **六节点执行流程**：见 `generate-docs-agent.md`
- **文档类型映射**：见 `generate-docs-agent.md`
- **质疑环节机制**：见 `generate-docs-agent.md`

---

*本命令是 `generate-docs-agent` 的快捷入口，底层使用 Task 工具调用 agent 执行*
