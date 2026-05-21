---
name: patent-tech-disclosure
description:  生成或完善技术交底书（专利申请前的内部技术文档）。支持两种模式：生成模式（从技术方案/创意从头生成完整交底书）和完善模式（基于已有交底书+定向修改要求，在已有基础上修改特定章节）。适用于"生成技术交底书"、"完善交底书"、"补充交底书"、"技术披露"等场景。与专利申请文件（patent-patent-writing）不同，交底书是给专利代理
  人看的原始技术材料，需要深入的技术分析和可复现的细节描述。
---

---

# 技术交底书生成与完善工作流

## 双模式说明

本 Skill 支持两种工作模式，根据用户输入自动判断：

| 模式 | 触发条件 | 输入 | 输出 |
|------|---------|------|------|
| **生成模式** | 用户未提供已有交底书，提供技术方案/创意 | 技术方案或创意 | 完整的新交底书 |
| **完善模式** | 用户提供了已有交底书 + 修改要求 | 已有交底书 + 定向修改要求 | 改进后的交底书 |

### 模式判断逻辑

```
IF 用户提供了已有交底书文件内容 AND 存在明确的修改/补充要求 THEN
    → 完善模式
ELSE
    → 生成模式
END IF
```

### 完善模式的典型场景

| 场景 | 用户指令示例 |
|------|------------|
| 定向补强 | "把数据流向说清楚""补充实施例的具体处理过程" |
| 追加内容 | "补附图标记表""加一个教育场景的故事""加入云-边-端架构" |
| 诊断性补强 | "完善专利技术交底书"（未指定具体方向，需系统先诊断） |
| 基于质疑补强 | 基于质疑者的反馈补充技术细节 |

## ⚠️ 核心原则：专利代理人视角

技术交底书的目标读者是**专利代理人**，不是投资人、学术同行或产品经理。

撰写前必须阅读：`references/agent-constraints.md`

**代理人关心的核心问题：**
1. 这个技术方案怎么写成权利要求？（需要具体技术特征）
2. 这个技术方案和现有技术的区别在哪里？（需要具体缺陷）
3. 这个技术方案的技术效果是什么？（需要技术效果，不是商业效果）

## ⚠️ 强制执行标记

以下步骤必须执行，不可跳过：

**准备工作**
- [ ] 信息收集

**分析阶段**（需要完成的任务）
- [ ] 技术深度分析（必须完成所有自查）
- [ ] 整体架构构建与创新点关联性分析（必须绘制技术架构图，完成关联性判断）
- [ ] 技术问题筛选（最多1-2个）

**撰写阶段**（遵循规范生成文档）
- [ ] 文档生成（必须按 structure-guide.md 生成，含附图 Mermaid 代码≥2幅）
- [ ] 创新点结构模板（必须按 innovation-point-template.md 执行）
- [ ] 遵循核心撰写原则（必须按 writing-principles.md 执行）
- [ ] 遵循 LaTeX 格式规范（必须按 latex-syntax.md 执行）

**执行阶段**
- [ ] 质量检查（必须通过 quality-checklist.md）

**⚠️ 如果跳过以上任何步骤，生成的文档将不符合要求！**

---

## 参考资源

### 任务流程文件（需按步骤完成）
- `references/info-collection.md` — 信息收集流程
- `references/agent-constraints.md` — 📌 **必须首先阅读**：专利代理人视角约束
- `references/analysis.md` — 技术深度分析流程（含三要素对应性检查）
- `references/architecture.md` — 架构构建与创新点关联性分析流程
- `references/problem-filtering.md` — 技术问题筛选流程

### 撰写规范文件（撰写时需反复查阅）
- `assets/templates/structure-guide.md` — 文档结构模板
- `assets/templates/innovation-point-template.md` — 创新点详细结构模板（撰写时需遵循）
- `references/writing-principles.md` — 核心撰写原则
- `references/latex-syntax.md` — LaTeX 格式规范

### 质量检查文件
- `assets/templates/quality-checklist.md` — 质量检查清单
- `references/agent-self-check.md` — 📌 **生成后必须执行**：代理人视角自检验证

### 示例文件
- `assets/examples/` — Few-shot 示例文件

---

## 执行流程

按以下顺序执行，详见对应文件：

**准备工作**
1. 📌 **专利代理人视角约束** → `references/agent-constraints.md` （**必须首先阅读**）
2. 信息收集 → `references/info-collection.md`

**分析阶段**（需要完成的任务）
3. 技术深度分析（含三要素对应性检查） → `references/analysis.md`
4. 整体架构构建与创新点关联性分析 → `references/architecture.md`
5. 技术问题筛选 → `references/problem-filtering.md`

**撰写阶段**（遵循规范生成文档）
5. 文档生成（遵循 `assets/templates/structure-guide.md`）
6. 撰写创新点时遵循 → `assets/templates/innovation-point-template.md`
7. 遵循核心撰写原则 → `references/writing-principles.md`
8. 遵循 LaTeX 格式规范 → `references/latex-syntax.md`

**执行阶段**
6. 质量检查 → `assets/templates/quality-checklist.md`
7. 📌 **代理人视角自检验证** → `references/agent-self-check.md` （**必须执行**）

---

## 完善模式执行流程

当判断为完善模式时，按以下流程执行（不走生成模式的完整7阶段）：

### 步骤1：诊断问题

1. 读取已有交底书全文
2. 分析用户的修改要求
3. 如果用户未指定具体方向（"完善交底书"），则先执行诊断：
   - 按 `references/agent-self-check.md` 的标准逐项检查
   - 输出诊断结果，向用户展示哪些章节需要补强
   - 等待用户确认后再执行修改

### 步骤2：定向修改

按用户要求（或诊断结果）逐项修改交底书：

| 修改类型 | 处理方式 |
|---------|---------|
| 补充数据流描述 | 分析模块间关系，按 `references/analysis.md` 的技术深度标准补充 |
| 补充实施例 | 按用户指定的场景，撰写完整的实施过程（输入→处理→输出） |
| 补充附图标记表 | 遍历附图代码中的标记，生成标记-名称对照表 |
| 补充系统部署描述 | 补充物理/逻辑部署架构说明 |
| 修正技术细节 | 读取 `references/agent-constraints.md` 确保修改后仍符合代理人视角 |

### 步骤3：修改后自检

修改完成后执行快速自检：

```
[ ] 修改后的章节是否与文档其他部分一致
[ ] 是否引入了新的逻辑矛盾
[ ] 技术术语使用是否前后一致
[ ] 新增内容是否充分（代理人能理解、技术人员能实施）
```

### 步骤4：输出

- **修改后交底书**：保留原文档结构，仅修改指定章节
- **修改记录**：列出每处修改的位置和内容
- **命名**：`技术交底书_[发明名称]_[YYYYMMDDHHMMSS]_enhanced.md`

---

## 输出规范

### 生成模式输出

- **格式**：Markdown (.md)
- **命名**：`技术交底书_[发明名称]_[YYYYMMDDHHMMSS].md`
- **编码**：UTF-8
- **位置**：`./generated_docs/[YYYYMMDDHHMMSS]/`

### 完善模式输出

- **格式**：Markdown (.md)
- **命名**：`技术交底书_[发明名称]_[原时间戳]_enhanced.md`
- **编码**：UTF-8
- **位置**：与原交底书同目录
