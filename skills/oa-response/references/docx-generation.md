# Word 文档生成与修订标记规范

## 目录

- [核心原则](#核心原则)
- [最终输出文件清单](#最终输出文件清单)
- [一、意见陈述书 Word 文档生成](#一意见陈述书-word-文档生成)
- [二、修改对照表 Word 文档生成](#二修改对照表-word-文档生成)
- [三、修改后权利要求书（干净版）Word 文档生成](#三修改后权利要求书干净版word-文档生成)
- [四、修改后权利要求书（修订标记版）Word 文档生成](#四修改后权利要求书修订标记版word-文档生成)
- [五、质量检查](#五质量检查)

## 核心原则

默认输出 Markdown 格式。当用户明确要求 Word 格式时，执行本文件描述的 docx 生成流程。.md 内容作为撰写中间产物，用户要求 docx 时将其转换为格式化 Word 文档。

---

## 最终输出文件清单

| 文件 | 最终格式 | 生成方式 |
|------|---------|---------|
| 意见陈述书 | `.docx` | 先生成 .md 内容，再用 python-docx 转换为格式化 Word 文档 |
| 修改对照表 | `.docx` | 先生成 .md 表格，再用 python-docx 转换为 Word 表格 |
| 修改后权利要求书（干净版） | `.docx` | 先生成 .md 全文，再转换为 Word 文档（无任何标记，可直接作为替换页） |
| 修改后权利要求书（修订标记版） | `.docx` | 使用 python-docx 生成，基于修改对照表插入修订标记 |

**前置条件**：读取 `docx` Skill 了解 python-docx 的基础用法。

---

## 一、意见陈述书 Word 文档生成

```python
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# 默认字体
style = doc.styles['Normal']
style.font.name = '宋体'
style.font.size = Pt(12)

# 标题居中
title = doc.add_heading('意见陈述书', level=0)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

# 基本信息
doc.add_paragraph('申请号：XXXXXXXXXXXX.X')
doc.add_paragraph('发明名称：[发明名称]')
doc.add_paragraph('申请人：[申请人名称]')
doc.add_paragraph('审查意见通知书发文日：XXXX年XX月XX日')

# 各章节
doc.add_heading('一、答复概述', level=2)
doc.add_paragraph('[概述内容]')

doc.add_heading('二、对审查意见的逐一陈述', level=2)
# 每条审查意见对应一个子章节

doc.add_heading('三、关于修改的说明', level=2)
doc.add_paragraph('[修改说明]')

doc.add_heading('四、结论', level=2)
doc.add_paragraph('[结论]')

doc.save('意见陈述书_[发明名称].docx')
```

---

## 二、修改对照表 Word 文档生成

修改对照表是典型的宽表（6列），必须确保在 Word 页面视图下完整可读。

### 列宽分配与格式要求

| 列 | 建议宽度占比 | 字号 | 说明 |
|----|------------|------|------|
| 序号 | 5% | 小五（9pt） | 数字编号 |
| 权利要求 | 10% | 小五（9pt） | 如"权利要求1" |
| 修改位置 | 15% | 小五（9pt） | 定位描述 |
| 修改前（原文） | 25% | 小五（9pt） | 完整原文 |
| 修改后（新文） | 25% | 小五（9pt） | 完整新文 |
| 修改依据 | 20% | 小五（9pt） | 说明书段落号 |

**格式要点**：
- 表格总宽度 = 页面文本区域宽度（百分比 100%），禁止超出右边界
- 跨页时表头行自动重复（`tblHeader` 属性设为 true）
- 单元格内长文本自动换行，禁止溢出

### 生成代码

```python
from docx import Document
from docx.shared import Pt, Cm, Emu
from docx.oxml.ns import qn

doc = Document()
doc.add_heading('权利要求书修改对照表', level=1)
doc.add_paragraph('本次修改共涉及 [N] 处，涉及 [M] 条权利要求。')

# 表格宽度设置为页面文本区域 100%
table = doc.add_table(rows=1, cols=6, style='Table Grid')

# 设置表格自动适配页面宽度
tbl = table._tbl
tblPr = tbl.tblPr if tbl.tblPr is not None else tbl._add_tblPr()
tblW = tblPr.find(qn('w:tblW'))
if tblW is None:
    from lxml import etree
    tblW = etree.SubElement(tblPr, qn('w:tblW'))
tblW.set(qn('w:w'), '5000')
tblW.set(qn('w:type'), 'pct')  # 百分比

# 设置列宽比例（百分比：5%, 10%, 15%, 25%, 25%, 20% → 对应 250, 500, 750, 1250, 1250, 1000）
col_widths = [250, 500, 750, 1250, 1250, 1000]
for i, width in enumerate(col_widths):
    col = table.columns[i]
    for cell in col.cells:
        tc = cell._tc
        tcPr = tc.tcPr if tc.tcPr is not None else tc._add_tcPr()
        from lxml import etree
        tcW = tcPr.find(qn('w:tcW'))
        if tcW is None:
            tcW = etree.SubElement(tcPr, qn('w:tcW'))
        tcW.set(qn('w:w'), str(width))
        tcW.set(qn('w:type'), 'pct')

# 表头（设为跨页重复）
headers = ['序号', '权利要求', '修改位置', '修改前（原文）', '修改后（新文）', '修改依据']
header_row = table.rows[0]
# 设置表头行跨页重复
trPr = header_row._tr.get_or_add_trPr()
from lxml import etree
tblHeader = etree.SubElement(trPr, qn('w:tblHeader'))

for i, header in enumerate(headers):
    cell = header_row.cells[i]
    cell.text = header
    for p in cell.paragraphs:
        for run in p.runs:
            run.bold = True
            run.font.size = Pt(9)  # 小五

# 数据行
for 修改条目 in 修改列表:
    row = table.add_row()
    values = [
        修改条目['序号'], 修改条目['权利要求'], 修改条目['修改位置'],
        修改条目['修改前'], 修改条目['修改后'], 修改条目['修改依据']
    ]
    for i, val in enumerate(values):
        row.cells[i].text = val
        for p in row.cells[i].paragraphs:
            for run in p.runs:
                run.font.size = Pt(9)  # 小五

# 不超范围声明
p = doc.add_paragraph('')
run = doc.add_paragraph('以上所有修改均在原说明书和权利要求书记载范围内。').runs[0]
run.bold = True

doc.save('权利要求书修改对照表_[发明名称].docx')
```

---

## 三、修改后权利要求书（干净版）Word 文档生成

无任何修订标记，完整权利要求书全文，可直接作为替换页提交。

```python
from docx import Document
from docx.shared import Pt

doc = Document()
style = doc.styles['Normal']
style.font.name = '宋体'
style.font.size = Pt(12)

doc.add_heading('权利要求书', level=1)

for 权利要求 in 修改后的权利要求列表:
    p = doc.add_paragraph()
    run = p.add_run(f'{权利要求.编号}.')
    run.bold = True
    p.add_run(权利要求.正文)

doc.save('权利要求书（修改后）_[发明名称].docx')
```

---

## 四、修改后权利要求书（修订标记版）Word 文档生成

这是最关键的输出文件，需让审查员一眼看清每处修改。

### 4.1 修订标记样式

| 标记类型 | 视觉样式 | 适用场景 |
|---------|---------|---------|
| **删除的内容** | 红色字体 + 删除线 | 被删除或被替换的原文片段 |
| **新增的内容** | 红色字体 + 下划线 | 新写入的文字片段 |
| **整条删除** | 红色字体 + 删除线（覆盖整段） | 被完全删除的权利要求 |
| **未修改的内容** | 正常黑色字体 | 无变化的部分 |

### 4.2 标记粒度：按语义片段，不逐字

标记的最小单位是**有独立含义的词语或短语**，不是单个字。

| 修改类型 | 标记方式 | 示例（视觉效果） |
|---------|---------|-----------------|
| **替换** | ~~删除旧内容~~ 紧跟 <u>插入新内容</u> | ~~基于相似度计算~~ <u>基于余弦相似度计算，相似度阈值范围为0.7-0.95</u> |
| **删除** | 整段标红+删除线 | ~~3. 根据权利要求1所述的方法，还包括步骤C。~~ |
| **新增** | 新内容标红+下划线 | ...还包括<u>步骤C，其中步骤C采用注意力机制</u> |
| **合并（来源条目）** | 被合并的条目：整条标删除 | ~~3. 根据权利要求1...~~ |
| **合并（目标条目）** | 并入的内容标新增 | 1. 一种方法，包括A和B，<u>还包括步骤C</u> |
| **编号调整** | ~~旧编号~~ <u>新编号</u> | ~~3.~~ <u>3.</u> （原权4调整为新权3） |
| **引用关系变更** | ~~旧引用~~ <u>新引用</u> | ~~根据权利要求3~~ <u>根据权利要求1</u> 所述的方法 |

### 4.3 生成方式：调用预置脚本

**推荐方式**：使用 `scripts/generate_tracked_claims.py` 预置脚本生成修订标记版，避免手动操作 XML。

#### 步骤

**第一步：准备 JSON 数据文件**

将修改对照表的数据整理为 JSON 格式，保存为 `amendments.json`：

```json
{
  "invention_name": "XXX",
  "claims": [
    {
      "number": 1,
      "original_number": 1,
      "status": "modified",
      "original_text": "一种方法，包括步骤A...",
      "modified_text": "一种方法，包括步骤A和步骤B...",
      "segments": [
        {"type": "unchanged", "text": "一种方法，包括"},
        {"type": "deleted", "text": "步骤A"},
        {"type": "inserted", "text": "步骤A和步骤B"},
        {"type": "unchanged", "text": "，其特征在于..."}
      ]
    },
    {
      "number": 2,
      "original_number": 2,
      "status": "unchanged",
      "original_text": "根据权利要求1所述的方法...",
      "modified_text": "根据权利要求1所述的方法..."
    }
  ]
}
```

**字段说明**：
- `status`: `"unchanged"`（无修改）/ `"modified"`（有修改）/ `"deleted"`（整条删除）/ `"added"`（整条新增）
- `segments`: 仅 `modified` 状态需要，按语义片段拆分。每段 `type` 为 `"unchanged"` / `"deleted"` / `"inserted"`
- 如果不提供 `segments`，脚本会对整段原文和修改文做粗略对比标记

**第二步：调用脚本**

```bash
python scripts/generate_tracked_claims.py amendments.json "权利要求书（修订标记版）_[发明名称].docx"
```

脚本会自动生成带修订标记的 .docx 文件（删除=红色+删除线，新增=红色+下划线）。

#### 手动方式（备选）

如脚本不可用，可使用以下 python-docx 代码手动生成：

```python
from docx import Document
from docx.shared import Pt, RGBColor

doc = Document()
style = doc.styles['Normal']
style.font.name = '宋体'
style.font.size = Pt(12)

doc.add_heading('权利要求书（修订标记版）', level=1)


def add_deleted(paragraph, text):
    """删除标记：红色 + 删除线"""
    run = paragraph.add_run(text)
    run.font.color.rgb = RGBColor(0xFF, 0x00, 0x00)
    run.font.strike = True


def add_inserted(paragraph, text):
    """新增标记：红色 + 下划线"""
    run = paragraph.add_run(text)
    run.font.color.rgb = RGBColor(0xFF, 0x00, 0x00)
    run.underline = True


def add_normal(paragraph, text):
    """正常文本：黑色"""
    paragraph.add_run(text)


for 权利要求 in 全部权利要求列表:
    p = doc.add_paragraph()

    if 权利要求.整条删除:
        add_deleted(p, f'{权利要求.原编号}. {权利要求.原文}')
    elif 权利要求.有修改:
        if 权利要求.编号变化:
            add_deleted(p, f'{权利要求.原编号}.')
            add_inserted(p, f'{权利要求.新编号}.')
        else:
            add_normal(p, f'{权利要求.编号}.')
        for 片段 in 权利要求.文本片段列表:
            if 片段.类型 == "未修改":
                add_normal(p, 片段.内容)
            elif 片段.类型 == "删除":
                add_deleted(p, 片段.内容)
            elif 片段.类型 == "新增":
                add_inserted(p, 片段.内容)
            elif 片段.类型 == "替换":
                add_deleted(p, 片段.旧内容)
                add_inserted(p, 片段.新内容)
    else:
        add_normal(p, f'{权利要求.编号}. {权利要求.正文}')

doc.save('权利要求书（修订标记版）_[发明名称].docx')
```

---

## 五、质量检查

生成完成后，对照 SKILL.md 中的「质量检查」清单逐项检查。docx 生成阶段需特别关注：

- 所有输出文件均为 .docx 格式（中间产物 .md 可删除或保留，不作为交付物）
- 修订标记版中：
  - 删除内容为红色+删除线，新增内容为红色+下划线
  - 编号调整已分别标记旧编号和新编号
  - 引用关系变更已标记旧引用和新引用
  - 修订标记与修改对照表一一对应，无遗漏
