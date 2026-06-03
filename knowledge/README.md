# 知识库 (Knowledge Base)

本目录包含审核标准和参考知识库，供 document-reviewer-agent 和相关技能引用。

## 目录结构

```
knowledge/
├── README.md                        # 本文件
├── review-standards/                # 审核标准（按类别分组）
│   ├── patent/                     # 专利类审核标准
│   │   ├── patent-review.md       # 权利要求书审核标准
│   │   └── disclosure-review.md    # 技术交底书审核标准
│   ├── business/                   # 商业类审核标准
│   │   └── analysis-review.md      # 商业分析审核标准
│   ├── tech/                       # 技术类审核标准
│   │   └── solution-review.md      # 技术方案审核标准
│   ├── academic/                   # 学术类审核标准（待创建）
│   ├── reports/                    # 报告类审核标准（待创建）
│   └── strategy/                   # 策略类审核标准（待创建）
└── guidelines/                     # 审查指南和参考资料
    ├── patent-examination-guidelines-2023.md            # 专利审查指南2023版本
    ├── ai-patent-examination-issues.md
    ├── cn-patent-35-key-issues.md
    └── patent-guide-amendment-comparison-2026.md            # 专利审查指南 - 修订内容 - 对比表 - 2026.md
```

## 使用方式

### 通过 document-reviewer-agent 自动使用（推荐）

审核 Agent 会根据 `skill_used` 自动查找对应的审核标准文件：

```
调用: document-reviewer-agent
参数: skill_used = "tech-disclosure"
→ 自动查找: review-standards/patent/disclosure-review.md
→ 读取评分维度、检查清单等
→ 生成审核报告
```

**Skill → 标准文件映射**（在 document-reviewer-agent 中定义）：

| Skill 名称 | 标准文件路径 |
|-----------|-------------|
| `tech-disclosure` | review-standards/patent/disclosure-review.md |
| `technical-tech-solution` | review-standards/tech/solution-review.md |
| `business-analysis` | review-standards/business/analysis-review.md |

### 直接引用审核标准文件

在 `SKILL.md` 或 `AGENT.md` 中通过相对路径引用：

```markdown
## 审核阶段

**生成完成后，执行审核：**

1. 读取审核标准：`../../knowledge/review-standards/patent/disclosure-review.md`
2. 按照标准进行检查和评分
```

## 目录组织原则

1. **按类别分组**：审核标准按文档类型分类到不同目录
2. **单一职责**：每个审核标准文件只包含一个文档类型的审核规则
3. **可复用性**：通用的审查指南可被多个审核标准引用
4. **版本控制**：所有修改通过 git 追踪

## 添加新审核标准

当添加新的 skill 时：

1. **选择分类**：确定文档类型属于哪个分类
2. **创建审核标准**：在对应目录下创建 `{name}-review.md` 文件
3. **更新映射**：在 `document-reviewer-agent.md` 的映射表中添加记录

**示例**：添加专利创新评估审核标准

```bash
# 1. 创建审核标准文件
touch review-standards/patent/innovation-review.md

# 2. 编辑文件内容（参考其他审核标准格式）

# 3. 更新 document-reviewer-agent.md 映射表
# 添加行: | innovation-assessment-report | review-standards/patent/innovation-review.md | 80 |
```

## 审核标准文件格式规范

每个审核标准文件应包含：

```markdown
# {文档类型} 审核标准

## 评分标准

### 综合评分计算
```
总分 = 维度1(权重) + 维度2(权重) + ...
```

### 评级标准
| 等级 | 分数范围 | 建议 |
|------|----------|------|
| 优秀 | 90-100 | 可以直接使用 |
| 良好 | 80-89 | 稍作优化后使用 |
...

---

## 一、{维度1名称} ({权重%)

### 检查清单
- [ ] 检查项1
- [ ] 检查项2

### 评分标准
- ⭐⭐⭐⭐⭐ 完美标准
- ⭐⭐⭐⭐ 良好标准
...

---

**文档版本**: vX.X
**最后更新**: YYYY-MM-DD
```

## 当前审核标准状态

| 分类 | 文档类型 | 标准文件 | 状态 |
|------|----------|----------|------|
| patent | 技术交底书 | disclosure-review.md | ✅ |
| patent | 权利要求书 | patent-review.md | ✅ |
| tech | 技术方案 | solution-review.md | ✅ |
| business | 商业分析 | analysis-review.md | ✅ |
| academic | 工程论文 | engineering-paper-review.md | ❌ 待创建 |
| academic | 科学论文 | science-paper-review.md | ❌ 待创建 |
| academic | 经济论文 | economy-paper-review.md | ❌ 待创建 |
