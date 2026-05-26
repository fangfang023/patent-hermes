# 专利智能生成系统 · 编排入口（Hermes Project Rules）

> 本文件由 Hermes 在项目根目录自动注入。
> 它定义"做什么、按什么顺序做、产出长什么样"；
> 具体实现由 `skills/` 和 `agents/` 下的定义承担，
> `knowledge/` 提供法律参考和审核标准。

## 1. 项目目标

把"用户输入（技术创意 / 交底素材 / 审查意见 / 论文等）"转换为一整套专利文档：

- **输入**：
  - 技术创意描述、交底素材（必填）
  - 可选：创意数量、文档类型偏好、特定要求
- **输出**：`output/` 或 `generated_docs/` 下的 `.md` / `.docx` 文件

## 2. 目录约定

| 路径 | 用途 | 谁维护 |
|------|------|--------|
| `agents/` | 编排指令模板（子代理的 context 来源） | 智能体工程师 |
| `skills/` | Hermes Skill 定义（文档生成技能） | 智能体工程师 |
| `knowledge/guidelines/` | 专利审查指南、AI 专利审查问题等 | 专利专家 |
| `knowledge/references/` | 权利要求撰写规则、分案标准等 | 专利专家 |
| `knowledge/review-standards/` | 各类文档审核标准 | 专利专家 |
| `knowledge/workflows/` | 端到端执行流程定义 | 智能体工程师 |
| `hooks/` | Shell hooks（上下文注入、任务验证） | 工程师 |
| `commands/` | Claude Code 自定义命令 | 工程师 |
| `scripts/` | 启动 / 停止 / 配置脚本 | 工程师 |
| `docker/` | Docker 部署定义 | 工程师 |
| `output/` | 最终产物目录 | 系统自动写入 |
| `workflows/` | 端到端流程定义 | 智能体工程师 |

## 3. 触发与路由分流

### 3.1 路由判定（进入 Agent 调用之前必须先判定）

每一条用户消息，主 Claude 先做一次"路由判定"，决定走哪条流水线：

| 路由 | 触发条件 | 走哪条 |
|------|---------|--------|
| **交底书** | 消息涉及技术交底书（生成 / 完善 / 多轮） | `disclosure-agent` |
| **专利撰写** | 消息涉及权利要求书、说明书、全套专利申请文件 | `patent-drafting-agent` |
| **审查答复** | 消息涉及审查意见通知书、驳回复审 | `prosecution-agent` |
| **批量专利** | 消息涉及批量生成、多篇专利 | `batch-patent-generator` → `single-creative-generator` |
| **质疑** | 消息涉及质疑交底书或权利要求书 | `patent-challenger-agent` |
| **审核** | 消息涉及文档质量审核、打分评审 | `document-reviewer-agent` |
| **单次 Skill** | 用户说"快速""草稿""初稿"，或只做单步操作 | 主 Claude + 对应 Skill 直出 |
| **讨论/咨询** | "什么是...""为什么...""怎么理解...""可行吗？" | 主 Claude 直接回答 |
| **下载文件** | "下载""发给我""我要文件""文件在哪""下载链接" | 主 Claude 扫描 output/ 并输出下载链接（见 §13） |
| **简单修改** | 补附图标记、改某段措辞、加个表格 | 主 Claude 直接用 Edit/Read 操作 |

### 3.2 路由决策流程

```
用户请求
  │
  ├─ 显式指定 Agent/Skill？ → 直接路由
  │
  ├─ 讨论/咨询/提问？
  │    → 主 Agent 直接回答（不调用 delegate_task 或 Skill）
  │
  ├─ 下载/发文件？
  │    → 主 Agent 扫描 output/，输出下载链接（见 §13）
  │
  ├─ 简单修改？
  │    → 主 Agent 直接操作
  │
  ├─ 审查/答复/驳回复审？
  │    → delegate_task(goal="答复审查意见。第一步：Read .../agents/prosecution-agent.md...")
  │
  ├─ 交底书相关？
  │    → delegate_task(goal="生成交底书。第一步：Read .../agents/disclosure-agent.md...")
  │
  ├─ 专利撰写相关？
  │    → delegate_task(goal="撰写专利。第一步：Read .../agents/patent-drafting-agent.md...")
  │    → 完成后自动追加溯源映射表 delegate_task
  │
  ├─ 批量专利？
  │    → 阶段1: delegate_task(goal="批量生成。第一步：Read .../agents/batch-patent-generator.md...")
  │    → 阶段2: 逐个 delegate_task(goal="单创意生成。第一步：Read .../agents/single-creative-generator.md...")
  │
  ├─ 单次质疑/审核？
  │    → 对应 delegate_task(goal 中指引 Read 对应 agent .md)
  │
  └─ 用户说"快速""草稿""初稿"？
       → 主 Agent + 对应 Skill 直出（不走 delegate_task）
```

## 4. Agent / Skill 体系

### 4.1 Agent 列表

| Agent | 预加载 Skills | 用途 | maxTurns |
|-------|-------------|------|----------|
| disclosure-agent | patent-tech-disclosure, patent-challenger, utils-document-reviewer, utils-innovation-checker | 交底书生成/完善/质疑循环 | 60 |
| patent-drafting-agent | patent-claims-writing, patent-patent-writing, patent-challenger | 专利撰写管线（权利要求→说明书→全套） | 100 |
| prosecution-agent | patent-office-action-response, patent-claims-review-and-amendment, patent-reexamination-response, patent-law-reference | 审查答复管线 | 60 |
| batch-patent-generator | paper-engineering-paper, paper-science-paper, paper-economy-paper | 批量前置：论文生成+创意挖掘 | 100 |
| single-creative-generator | patent-patent-writing, patent-product-plan, technical-tech-solution, patent-operation-plan, patent-ip-strategy | 单创意全套生成（专利+4种方案） | 200 |
| patent-challenger-agent | patent-challenger | 对抗式质疑 | 20 |
| document-reviewer-agent | utils-document-reviewer, utils-innovation-checker | 结构化质量审核 | 20 |

### 4.2 Skill 分类

#### 专利文档类
| Skill | 用途 |
|-------|------|
| patent-tech-disclosure | 技术交底书（生成/完善） |
| patent-claims-writing | 权利要求书 |
| patent-patent-writing | 全套专利申请文件 |
| patent-office-action-response | 答复审查意见 |
| patent-claims-review-and-amendment | 权利要求审查与修改 |
| patent-reexamination-response | 驳回复审分析 |
| patent-divisional-analysis | 分案布局分析 |
| patent-innovation-splitter | 创新点智能切分 |
| patent-traceability-mapping | 权利要求溯源映射表 |
| patent-business-analysis | 商业价值分析 |
| patent-ip-strategy | IP 保护策略 |
| patent-product-plan | 产品方案 |
| patent-operation-plan | 运营方案 |
| patent-classification-reference | 关键数字技术专利分类匹配 |
| patent-law-reference | 专利法律参考 |
| patent-us-review | 美标专利评审 |

#### 技术文档类
| Skill | 用途 |
|-------|------|
| technical-tech-solution | 技术方案 |
| technical-value-proposition | 价值主张 |
| technical-thesis-doc | 立论白皮书 |
| technical-project-feasibility-assessment-report | 项目可行性评估 |
| technical-ethics-report | 伦理风险评估 |
| technical-standard-doc | 合规标准策略 |

#### 学术论文类
| Skill | 用途 |
|-------|------|
| paper-engineering-paper | 工程论文 |
| paper-science-paper | 科学论文 |
| paper-economy-paper | 经济论文 |

#### 工具类
| Skill | 用途 |
|-------|------|
| pdf | PDF 文档处理 |
| docx | Word 文档处理 |
| pptx | PowerPoint 文档处理 |
| patent-challenger | 专利质疑技能 |
| utils-document-reviewer | 文档审核执行器 |
| utils-innovation-checker | 创新性与重复度检测 |
| interactive-report | 交互式报告 |
| skill-creator | Skill 创建器 |

## 5. delegate_task 调用规则

### 5.1 核心原则

Hermes 原生不支持"Agent 定义文件"注册机制。`agents/*.md` 是**编排指令模板库**，不是 Hermes 的注册入口。

调用 `delegate_task` 时遵循以下规则：

- **goal 字段**：写任务目标 + 指引子代理去 Read 对应的 agent .md 文件
- **context 字段**：只写必要的数据（用户输入内容、文件路径、参数），**不写编排指令模板**
- 子代理会在独立窗口中自己 Read 指令文件，然后严格按指令执行

### 5.2 标准调用模板

```python
delegate_task(
    goal="{任务目标描述}。第一步：Read {工作目录}/agents/{agent-name}.md，严格按其中的编排流程执行。",
    context="用户输入：{创意描述/审查意见/交底素材}。工作目录：{PROJECT_ROOT}。输出目录：output/",
    toolsets=["terminal", "file"],
    role="orchestrator"  # 仅当子代理需要继续派发子任务时使用
)
```

### 5.3 各 Agent 调用示例

**交底书**：
```python
delegate_task(
    goal="生成技术交底书。第一步：Read /app/patent-hermes-agent/agents/disclosure-agent.md，严格按其中的编排流程执行。",
    context="用户创意描述：{创意内容}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"],
    role="orchestrator"
)
```

**专利撰写**：
```python
delegate_task(
    goal="撰写全套专利申请文件。第一步：Read /app/patent-hermes-agent/agents/patent-drafting-agent.md，严格按其中的编排流程执行。phase={claims|specification|abstract|full}。",
    context="前置文件：{交底书/技术方案路径}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"],
    role="orchestrator"
)
```

**审查答复**：
```python
delegate_task(
    goal="答复审查意见。第一步：Read /app/patent-hermes-agent/agents/prosecution-agent.md，严格按其中的编排流程执行。",
    context="审查意见文件：{OA文件路径}。原始权利要求：{权利要求书路径}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"],
    role="orchestrator"
)
```

**质疑**：
```python
delegate_task(
    goal="质疑文档。第一步：Read /app/patent-hermes-agent/agents/patent-challenger-agent.md，严格按其中的质疑流程执行。",
    context="待质疑文件：{交底书/权利要求书路径}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"]
)
```

**审核**：
```python
delegate_task(
    goal="审核文档质量。第一步：Read /app/patent-hermes-agent/agents/document-reviewer-agent.md，严格按其中的审核流程执行。",
    context="待审核文件：{文档路径}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"]
)
```

### 5.4 工作目录路径说明

| 运行环境 | PROJECT_ROOT（agent .md 的 Read 路径前缀） |
|---------|------------------------------------------|
| Docker 容器 | `/app/patent-hermes-agent` |
| 本地终端 | 项目实际绝对路径（如 `/Users/ff/PycharmProjects/patent/patent-hermes`） |

### 5.5 role 参数选择

| Agent | role | 原因 |
|-------|------|------|
| disclosure-agent | `orchestrator` | 需要派发质疑子任务 |
| patent-drafting-agent | `orchestrator` | 需要派发质疑子任务 |
| prosecution-agent | `orchestrator` | 可能需要派发法律查找子任务 |
| batch-patent-generator | `orchestrator` | 需要派发论文生成子任务 |
| single-creative-generator | `orchestrator` | 需要派发多个 Skill 子任务 |
| patent-challenger-agent | `leaf`（默认） | 单步质疑，不需要继续派发 |
| document-reviewer-agent | `leaf`（默认） | 单步审核，不需要继续派发 |

## 6. 专利撰写后自动串联溯源映射表

当 patent-drafting-agent 子代理返回的摘要中包含全套专利文件路径时（phase=full 或 phase=abstract 成功），主 Agent **自动追加一步**：

```python
delegate_task(
    goal="生成权利要求溯源映射表。第一步：Read /app/patent-hermes-agent/skills/patent-traceability-mapping/SKILL.md，严格按其中的流程执行。传入权利要求书、说明书、原始输入文件三份路径。",
    context="权利要求书路径：{claims_path}。说明书路径：{spec_path}。原始输入路径：{input_path}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"]
)
```

**注意**：
- 如果用户说"快速""草稿""初稿"，跳过溯源映射表自动串联
- 如果用户主动要求"生成溯源表""映射表"，直接 delegate_task 而不经过 patent-drafting-agent

## 7. 批量专利编排

当用户意图为批量专利生成时，按两阶段执行：

**阶段1**：派发 batch-patent-generator 生成论文 + 创意清单

```python
delegate_task(
    goal="批量生成论文并挖掘创意。第一步：Read /app/patent-hermes-agent/agents/batch-patent-generator.md，严格按其中的流程执行。返回创意清单结构化数据。",
    context="用户创意描述：{创意内容}。创意数量：{N}。工作目录：/app/patent-hermes-agent。输出目录：output/",
    toolsets=["terminal", "file"],
    role="orchestrator"
)
```

阶段1 返回后，从子代理摘要中提取创意清单（包含 BASE_DIR、TIMESTAMP、PAPER_FILES、CREATIVES）。

**阶段2**：逐个创意派发 single-creative-generator

⚠️ 阶段2 开始前，主 Agent 必须先梳理创意清单，然后逐个派发子代理。

对每个创意**逐个**调用 delegate_task（不要并行，一次一个）：

```python
# 对每个创意逐个执行：
delegate_task(
    goal="为创意{创意编号}生成全套专利+方案。第一步：Read /app/patent-hermes-agent/agents/single-creative-generator.md，严格按其中的流程执行。",
    context="创意编号：{N}。创意标题：{title}。技术方向：{direction}。创新点：{innovation}。商业价值：{value}。用户原始创意：{原始描述}。论文文件路径：{paper_paths}。工作目录：/app/patent-hermes-agent。输出目录：{BASE_DIR}/创意{N}/",
    toolsets=["terminal", "file"],
    role="orchestrator"
)
```

**关键要求**：
- 每个子代理独立拥有完整上下文窗口，互不影响
- 逐个执行，不要并行分发
- 单个创意子代理失败时记录错误，继续处理下一个
- 子代理返回的摘要仅供判断状态，不要重新输出或总结其内容
- 断点续传：派发前先检查目标目录是否已有 ≥7 个 .md 文件，已有则跳过

## 8. 输出契约

### 8.1 文档生成路径规则

- 所有文档生成操作在项目根目录下执行
- 文档默认输出到 `output/` 或 `generated_docs/` 目录
- 输出文件命名格式：`[文档类型]_[创意简述]_[时间戳].md`

### 8.2 文件交付方式

文件生成后，**必须**在回复中提供 Output Server 下载链接，用户通过该链接直接下载文件。

下载链接格式：`http://192.168.8.234:9107/{文件名}`（本地）或 `http://{服务器IP}:9107/{文件名}`（远程/Docker）

禁止仅回复"文件路径为 XXX"而不提供下载链接——飞书用户无法访问服务器文件系统路径。

**多文件交付**：当一次任务生成多个文件时，**必须逐一列出**每个文件的下载链接，禁止只给出目录链接。

```
📎 文件已生成，点击下载：
1. 权利要求书：http://{IP}:{PORT}/{path}/权利要求书_xxx.md
2. 说明书：http://{IP}:{PORT}/{path}/说明书_xxx.md
3. 摘要与附图说明：http://{IP}:{PORT}/{path}/摘要与附图说明_xxx.md
```

**批量目录交付**：批量专利生成完成后，按创意分组列出每个文件：

```
📎 批量专利文件已生成，共 N 个创意：
📁 创意1：
   - 权利要求书：http://{IP}:{PORT}/{path}/创意1/权利要求书_xxx.md
   - 说明书：http://{IP}:{PORT}/{path}/创意1/说明书_xxx.md
   - ...
📁 创意2：
   - ...
```

### 8.3 批量专利输出目录结构

```
output/
└── 创意_{timestamp}/
    ├── 论文_工程_{创意1简述}.md
    ├── 论文_科学_{创意1简述}.md
    ├── 论文_经济_{创意1简述}.md
    ├── 创意清单.json
    ├── 创意1/
    │   ├── 权利要求书_{简述}.md
    │   ├── 说明书_{简述}.md
    │   ├── 摘要_{简述}.md
    │   ├── 产品方案_{简述}.md
    │   ├── 技术方案_{简述}.md
    │   ├── 运营方案_{简述}.md
    │   └── IP保护策略_{简述}.md
    ├── 创意2/
    │   └── ...（同结构）
    └── 溯源映射表_{简述}.md
```

## 9. 强约束（违反视为失败）

1. **`write_file` / `Edit` 直写**：所有 `.md` / `.docx` 必须用 `write_file`/`edit_file`/`Write`/`Edit` 直接落盘；**禁止** `execute_code` / `terminal heredoc` / Python 脚本批量造文件。
2. **不臆造法律**：审查指南内容必须来自 `knowledge/guidelines/`；权利要求规则必须来自 `knowledge/references/`；审核标准必须来自 `knowledge/review-standards/`。
3. **占位符必须替换**：`{发明名称}` / `{技术领域}` / `{{parent.content}}` 等模板占位符不得原样出现在输出文件中。
4. **路径锁定**：写入路径必须以 `output/` 或 `generated_docs/` 为前缀，禁止越界。
5. **leaf 子代理不嵌套派发**：`role="leaf"` 的子代理不能再发起 `delegate_task`；需要派发子任务时必须指定 `role="orchestrator"` 并确保 `delegation.max_spawn_depth ≥ 2`。
6. **禁止"备用文件/占位内容"反模式**：如果 Worker 因截断/超时/网络抖动失败，**只能真正重试**，**绝对不允许**写"备用文件"/"占位内容"/"标准模板占位"等假文本来骗过质量检查。
7. **重试上限**：Agent 单个阶段重试 ≤ 2 次；仍失败 → 单阶段标 `partial`，**不写假文档**。
8. **质疑必须尖锐**：patent-challenger-agent 的质疑必须从审查员视角出发，指出实质缺陷，不允许温和/敷衍的质疑。
9. **溯源映射表必串联**：专利撰写完成后（非快速/草稿模式），必须自动生成溯源映射表，串联权利要求→说明书→原始输入。

## 10. 异常处理

### 10.1 输入缺失

- 用户未提供技术创意/交底素材 → **反问补齐**，禁止凭空虚构
- 用户仅说"帮我写个专利" → 反问："请提供技术创意描述或交底素材"
- 交底素材过于模糊 → 反问要求补充具体技术细节

### 10.2 Agent 失败处理

| 场景 | 处理方式 |
|------|---------|
| 单阶段失败 | 重试 1 次，仍失败标记 partial，继续下一阶段 |
| 全流程失败率 > 50% | 终止流程，通知用户 |
| 批量中单个创意失败 | 记录错误，继续处理下一个创意 |
| 质疑循环陷入死循环 | 最多 3 轮质疑-修改，3 轮后强制终止并交付当前版本 |

### 10.3 模式说明

| 模式 | 触发关键词 | 行为 |
|------|-----------|------|
| **交底书生成** | "交底书""技术交底""生成交底书" | disclosure-agent |
| **交底书完善** | "完善交底书""补充交底书""改进交底书" | disclosure-agent（完善模式） |
| **权利要求** | "权利要求""权利要求书""撰写权利要求" | patent-drafting-agent（phase=claims） |
| **全套专利** | "全套""完整专利""专利申请" | patent-drafting-agent（phase=full） |
| **审查答复** | "审查意见""OA""答复审查""驳回" | prosecution-agent |
| **批量生成** | "批量""多篇""几个专利""生成多个" | batch-patent-generator → single-creative-generator |
| **快速/草稿** | "快速""草稿""初稿""简版" | 主 Claude + Skill 直出（不走 Agent） |
| **下载文件** | "下载""发给我""我要文件""文件在哪""下载链接" | 主 Claude 扫描 output/ 输出下载链接（§13） |

## 11. 速查命令

> **注意**：§12、§13 为新增规则，与 §1-§11 同等约束力。

## 12. 进度反馈规则

用户在等待过程中必须获得实时进度反馈，**禁止"黑箱等待"**。

### 12.1 主 Agent 反馈义务

主 Agent 在调用子 Agent（`delegate_task`）前后，**必须**向用户输出进度消息：

| 时机 | 必须输出内容 |
|------|------------|
| 调用子 Agent 前 | 告知用户即将执行的任务名称、预估耗时 |
| 子 Agent 返回后 | 告知用户该阶段完成状态和产出摘要 |
| 批量任务每个批次完成后 | 告知当前进度（如"已完成创意 3/10"） |
| 全部任务完成后 | 输出最终汇总 + 所有下载链接 |

### 12.2 反馈消息格式

```
# 调用子 Agent 前
🔄 正在启动「{任务名称}」，预计需要 {N} 分钟，请稍候...

# 子 Agent 返回后
✅ 「{任务名称}」已完成，{一句话摘要}

# 批量进度
📊 进度：已完成 {已完成数}/{总数}（{创意标题} ✓）

# 全部完成
✅ 全部任务完成！
{文件下载链接列表}
```

### 12.3 批量专利特殊规则

批量专利流程（§7）中，主 Agent 必须在每个子 Agent 返回后向用户输出进度：

```
阶段1完成 → 输出："✅ 论文生成+创意挖掘完成，发现 {N} 个可专利创意，开始逐个生成..."
阶段2 每个创意完成 → 输出："📊 创意 {i}/{total} 「{标题}」生成完成"
阶段2 全部完成 → 输出最终汇总 + 全部文件下载链接
```

### 12.4 禁止行为

- **禁止**：调用子 Agent 后一言不发直到最终结果返回
- **禁止**：只在最后一步才输出所有信息
- **禁止**：输出技术性的内部日志（如 delegate_task 的原始参数），用户只需要人类可读的进度消息

## 13. 下载意图识别与文件交付规则

### 13.1 下载意图识别

当用户消息匹配以下任意模式时，识别为「下载意图」：

| 意图关键词 | 示例 |
|-----------|------|
| "下载" | "下载文件"、"帮我下载" |
| "发给我" | "发给我吧"、"把文件发我" |
| "我要文件" | "我要文件"、"给我文件" |
| "获取文件" | "获取文件"、"拿文件" |
| "文件在哪" | "文件在哪"、"文件链接" |
| "下载链接" | "给我下载链接" |

### 13.2 下载意图处理流程

```
用户表达下载意图
  │
  ├─ 上下文中已有生成的文件？
  │    ├─ 是 → 直接输出文件下载链接（见 §13.3）
  │    └─ 否 → 扫描 output/ 目录，找到最近生成的文件，输出下载链接
  │
  ├─ 用户指定了具体文件名？
  │    ├─ 是 → 精确匹配并输出该文件的下载链接
  │    └─ 否 → 输出最近一次任务的所有文件下载链接
  │
  └─ output/ 目录为空？
       └─ 回复："当前没有已生成的文件。请先告诉我您的创意，我来为您生成专利文档。"
```

### 13.3 文件交付格式

#### 单文件

```
📎 您的文件已生成，点击下载：
http://192.168.8.234:{OUTPUT_PORT}/{文件名}
```

#### 多文件（逐一列出）

```
📎 文件已生成，点击下载：

1. {文件类型1}：http://192.168.8.234:{OUTPUT_PORT}/{文件名1}
2. {文件类型2}：http://192.168.8.234:{OUTPUT_PORT}/{文件名2}
3. {文件类型3}：http://192.168.8.234:{OUTPUT_PORT}/{文件名3}
```

#### 批量专利目录

```
📎 批量专利文件已生成，共 {N} 个创意：

📁 创意1：http://192.168.8.234:{OUTPUT_PORT}/{目录名}/创意1/
   - 权利要求书：http://192.168.8.234:{OUTPUT_PORT}/{目录名}/创意1/{权利要求书文件名}
   - 说明书：http://192.168.8.234:{OUTPUT_PORT}/{目录名}/创意1/{说明书文件名}
   - ...
📁 创意2：http://192.168.8.234:{OUTPUT_PORT}/{目录名}/创意2/
   - ...
```

### 13.4 强约束

1. **禁止**仅回复"文件路径为 /xxx/yyy.md"——飞书用户无法访问服务器文件系统路径
2. **必须**提供 HTTP 下载链接，格式为 `http://{服务器IP}:{OUTPUT_PORT}/{相对路径}`
3. **多文件时必须逐一列出**每个文件的下载链接，不要只给一个目录链接让用户自己找
4. 文件生成完成后（非下载意图场景），也**必须**附带下载链接，遵循 §8.2 规则

## 14. 模型失败处理规则

当模型调用出现网络错误、超时、无响应等情况时，按以下规则处理。

### 14.1 三级降级策略

```
模型调用失败
  │
  ├─ 第 1 级：同一模型重试 ≤ 3 次
  │    每次重试前输出：⚠️ 模型请求超时，正在重试（{n}/3）...
  │
  ├─ 第 2 级：3 次重试仍失败 → 切换备选模型
  │    输出：⚠️ 当前模型连续失败，正在切换到备选模型...
  │    （Hermes 框架的 fallback_providers 会自动切换，Agent 无需手动操作）
  │
  └─ 第 3 级：所有备选模型都失败 → 标记当前任务失败，跳过继续
       输出：❌ 所有模型均不可用，当前任务标记为失败，继续执行下一个任务。
```

### 14.2 Agent 行为规范

| 阶段 | Agent 必须做的事 |
|------|----------------|
| 检测到重试 | 向用户输出"⚠️ 网络不稳定，正在重试..." |
| 检测到模型切换 | 向用户输出"⚠️ 已自动切换到备选模型，继续执行..." |
| 单个文件生成失败 | 标记该文件为 `partial`，继续生成下一个文件，不阻塞整体流程 |
| 单个创意全部失败（批量场景） | 记录失败原因，输出"❌ 创意 {N} 生成失败：{原因}，继续处理下一个创意"，跳过继续 |
| 全部模型不可用 | 输出"❌ 所有模型暂时不可用，请稍后重试。已完成的部分文件已保存。" + 已完成文件的下载链接 |

### 14.3 批量任务失败容忍度

| 场景 | 处理方式 |
|------|---------|
| 单个文件失败 | 标记 partial，继续其余文件 |
| 单个创意全部文件失败 | 跳过该创意，继续下一个 |
| 失败率 > 50% | 终止流程，通知用户，交付已完成的部分文件 |
| 所有创意都失败 | 通知用户全部失败，建议稍后重试 |

### 14.4 用户沟通模板

```
# 重试中
⚠️ 网络不稳定，正在重试（{n}/3）...请耐心等待

# 模型切换
🔄 当前模型响应超时，已自动切换到备选模型继续执行

# 单个文件/创意失败
❌ 「{文件名/创意标题}」生成失败：{简要原因}
   已跳过，继续处理下一个...

# 部分完成
⚠️ 任务部分完成（{成功数}/{总数}）
   成功的文件已保存，点击下载：
   {下载链接列表}
   失败的任务：{失败列表}，建议稍后重试

# 全部失败
❌ 所有模型暂时不可用，未能完成文档生成。
   建议过几分钟后重新发送您的需求。
```

### 14.5 禁止行为

- **禁止**：模型失败后无限重试或卡死不动
- **禁止**：模型失败后不告知用户原因
- **禁止**：单个创意失败导致整个批量任务中断
- **禁止**：在失败时写"占位内容"或"备用文件"来掩饰失败（与 §9.6 一致）

```bash
# 先启动一次（自动配置 Hermes + 挂载 Skills + 安装 Hooks）
./scripts/start.sh

# 终端等效（与飞书消息一致；纯文本，无 `/` 前缀）
hermes -z "帮我生成一份技术交底书，创意是关于XXX"
hermes -z "帮我撰写权利要求书"
hermes -z "帮我答复审查意见"
hermes -z "批量生成3个专利"

# Docker 部署
cd docker && cp .env.example .env  # 填入 API Key
./docker/start.sh
```