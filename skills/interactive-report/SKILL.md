---
name: interactive-report
description: 生成交互式 HTML 长文报告。适用于解决方案、可行性分析、项目方案、培训方案、调研报告、年度总结等各类长文场景。输出带侧边栏导航、ECharts 图表、Mermaid 流程图的在线预览 HTML 页面。支持 2 万字以上的长文分块生成。当用户要求生成"报告""方案""规划""总结"且希望以 HTML 在线预览形式呈现时使用此 skill。
tools: Read, Write, Edit
---

# 交互式 HTML 报告生成工作流

## 角色定位

你是一名顶尖的报告撰写专家与技术文档架构师。你擅长将各类需求转化为结构清晰、视觉精美、交互丰富的在线报告。

## 目标

将用户输入的需求、方案、或现有 Markdown 文档，转化为一份可在线预览的交互式 HTML 报告，包含：
- 侧边栏目录导航（自动生成，滚动高亮）
- ECharts 数据可视化（雷达图、仪表盘、环形图等）
- Mermaid 流程图/架构图（自动渲染为 SVG）
- 统计卡片、彩色章节、进度条等视觉组件
- 响应式设计（桌面/平板/手机自适应）
- 导出为 PNG 图片功能

## 核心约束

1. **输出格式**：单文件 HTML（内联 CSS/JS，引用 CDN）
2. **字数要求**：不少于用户要求的字数（默认 2 万字）
3. **输出路径**：`outputs/[方案名称]_[YYYYMMDD].html`

---

## 工作流程

### 第一步：读取模板

使用 Read 工具读取 HTML 模板文件：

```
.claude/skills/interactive-report/templates/interactive-report.html
```

该模板包含完整的 CSS 设计系统、JS 交互逻辑和图表组件。模板中使用以下占位符标记内容注入点：

- `{{TITLE}}` — 页面标题
- `{{SUBTITLE}}` — 副标题/一句话描述
- `{{STATS_CARDS}}` — 统计卡片 HTML
- `{{NEXT_SECTION}}` — 章节内容注入点（核心占位符）
- `{{CHART_INIT}}` — ECharts 图表初始化代码

### 第二步：规划文档结构

基于用户输入，规划以下内容：

1. **标题和副标题**：提炼方案名称和核心定位
2. **统计卡片**（3-5 个）：关键量化指标（如 "70%+ 素养提升"、"85%+ 满意度"）
3. **章节大纲**：按逻辑拆分为 6-12 个一级章节，每个章节包含 2-5 个二级小节
4. **图表规划**：
   - 雷达图：出现"多维度评估/能力画像"时使用
   - 仪表盘：出现"评分/达标率/合格线"时使用
   - 环形图：出现"百分比统计/达成率"时使用
   - 柱状图：出现"对比分析/多组数据"时使用
5. **Mermaid 图**：描述流程、架构、层次关系时使用

### 第三步：复制模板为输出文件

将模板内容原样写入输出文件：

```
outputs/[方案名称]_[YYYYMMDD].html
```

使用 Write 工具，将模板的完整内容写入。

### 第四步：填充标题

使用 Edit 工具：

- 将 `{{TITLE}}` 替换为实际标题
- 将 `{{SUBTITLE}}` 替换为实际副标题

### 第五步：填充统计卡片

使用 Edit 工具，将 `{{STATS_CARDS}}` 替换为统计卡片 HTML。

统计卡片格式：
```html
<div class="stat-card" style="--card-color: var(--color-strategy)">
  <div class="stat-value">70%+</div>
  <div class="stat-label">普通教师数智素养提升</div>
</div>
```

可用的 CSS 变量颜色：
- `var(--color-strategy)` — 战略/蓝 (#1e3a8a)
- `var(--color-theory)` — 理论/绿 (#87a96b)
- `var(--color-target)` — 目标/橙 (#c65d07)
- `var(--color-arch)` — 架构/灰 (#78716c)
- `var(--color-growth)` — 发展/紫 (#7c3aed)

### 第六步：逐章节生成内容（核心：分块策略）

**这是最关键的步骤。** 为了突破模型单次输出 token 限制，采用分块注入策略：

**对于每个章节（一次处理一个章节）：**

1. 生成该章节的 HTML 内容片段，使用模板中定义的 CSS 类名
2. 使用 Edit 工具，将 `{{NEXT_SECTION}}` 替换为：
   ```
   [该章节的完整 HTML]

   {{NEXT_SECTION}}
   ```
3. 进入下一个章节，重复步骤 1-2
4. **最后一个章节完成后**，将 `{{NEXT_SECTION}}` 替换为空字符串

**每个章节的 HTML 结构示例：**

```html
<section class="chapter" style="--chapter-color: var(--color-strategy)" id="chapter-1">
  <div class="chapter-header">
    <h1>第一章 战略定位与问题诊断</h1>
  </div>

  <div class="chapter-body">
    <div class="content-card">
      <h2>1.1 项目背景与战略意义</h2>
      <p>正文内容...</p>
      <ul>
        <li>要点一</li>
        <li>要点二</li>
      </ul>
    </div>

    <div class="content-card">
      <h2>1.2 目标群体画像</h2>
      <div class="mermaid">
graph TD
    A[目标群体] --> B[地理层级]
    A --> C[学校层级]
      </div>
    </div>
  </div>
</section>
```

**章节色系分配规则：**

| 章节类型 | CSS 变量 | 适用内容 |
|---------|----------|---------|
| 战略/定位 | `--color-strategy` | 背景分析、问题诊断、目标定位 |
| 理论/框架 | `--color-theory` | 理论模型、框架设计、概念阐述 |
| 目标/指标 | `--color-target` | 目标体系、指标设计、达成标准 |
| 架构/平台 | `--color-arch` | 系统架构、技术方案、平台设计 |
| 发展/实施 | `--color-growth` | 实施路径、发展机制、持续改进 |

**图表触发规则：**

| 内容特征 | 图表类型 | HTML 代码 |
|---------|---------|-----------|
| 多维度评估（3+ 维度） | 雷达图 | `<div class="chart-container" id="chart-radar-1"></div>` |
| 评分/达标率 | 仪表盘 | `<div class="chart-container" id="chart-gauge-1"></div>` |
| 百分比统计 | 环形图 | `<div class="chart-container" id="chart-ring-1"></div>` |
| 多组数据对比 | 柱状图 | `<div class="chart-container" id="chart-bar-1"></div>` |
| 流程/架构/层次 | Mermaid | `<div class="mermaid">graph TD\n...</div>` |

**每个章节的字数要求：**
- 一级章节（含所有子节）：1,500-2,500 字
- 总共 8-12 个章节 = 约 12,000-30,000 字
- 如果用户要求 2 万字，需要 10-12 个章节，每章 1,800-2,000 字

**重要：每个章节必须内容充实。不要为了凑数而注水。每个段落至少 3-5 个有实质内容的句子。**

### 第七步：填充图表初始化代码

在所有章节都写入后，使用 Edit 工具将 `{{CHART_INIT}}` 替换为 ECharts 初始化代码。

格式示例：

```javascript
// 雷达图
if (document.getElementById('chart-radar-1')) {
  renderRadarChart('chart-radar-1', {
    indicators: [
      { name: '主体维度', max: 100 },
      { name: '本体维度', max: 100 },
      { name: '客体维度', max: 100 },
      { name: '发展维度', max: 100 }
    ],
    series: [{ name: '当前水平', value: [75, 68, 72, 65] }]
  });
}

// 仪表盘
if (document.getElementById('chart-gauge-1')) {
  renderGaugeChart('chart-gauge-1', {
    title: '创新性',
    value: 9.9
  });
}

// 环形图
if (document.getElementById('chart-ring-1')) {
  renderRingChart('chart-ring-1', {
    title: '素养提升率',
    value: 70,
    color: '#87a96b'
  });
}
```

### 第八步：审核

使用 Read 工具读取生成的文件，检查：
1. 所有占位符 `{{...}}` 是否已替换（搜索 `{{` 确认无残留）
2. HTML 标签是否闭合
3. 章节数量是否足够
4. 图表容器 ID 与初始化代码是否匹配

---

## 特殊处理：修改意见

当输入包含「修改意见」时：

1. 使用 Read 工具读取上一版 HTML 文件
2. 识别提取所有修改意见
3. 使用 Edit 工具对照原文执行针对性修改
4. 仅改动意见涉及部分，其他保持原样

## 特殊处理：已有 Markdown 文档

当用户提供了已有的 Markdown 文档时：

1. 使用 Read 工具读取该文档
2. 识别文档结构（标题层级、列表、代码块等）
3. 将 Markdown 转化为对应的 HTML 片段
4. 按照上述工作流程注入模板
5. 注意：将 Markdown 中的 ```mermaid 代码块转化为 `<div class="mermaid">` 标签

---

## 输出规范

- **格式**：HTML (.html)
- **编码**：UTF-8
- **位置**：`./outputs/`
- **命名**：`[方案名称]_[YYYYMMDD].html`

## 可用的图表函数

模板中已封装以下函数，可直接在 `{{CHART_INIT}}` 中调用：

### renderRadarChart(containerId, config)
```javascript
config = {
  indicators: [{ name: '维度名', max: 100 }],
  series: [{ name: '系列名', value: [数值数组] }]
}
```

### renderGaugeChart(containerId, config)
```javascript
config = {
  title: '评分项',
  value: 9.9  // 0-10 或 0-100
}
```

### renderRingChart(containerId, config)
```javascript
config = {
  title: '统计项',
  value: 70,  // 百分比数值
  color: '#87a96b'
}
```

### renderBarChart(containerId, config)
```javascript
config = {
  categories: ['类别1', '类别2'],
  series: [{ name: '系列名', data: [数值数组] }]
}
```
