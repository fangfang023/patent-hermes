#!/usr/bin/env python3
"""
权利要求书修订标记版 docx 生成脚本

输入：修改对照表的 JSON 文件（包含修改前后的权利要求）
输出：带修订标记的 .docx 文件（删除=红色+删除线，新增=红色+下划线）

使用方法：
  python generate_tracked_claims.py <amendments.json> <output.docx>

amendments.json 格式：
{
  "invention_name": "XXX",
  "claims": [
    {
      "number": 1,
      "original_number": 1,
      "status": "modified",          // "unchanged" | "modified" | "deleted" | "added"
      "original_text": "...",        // 修改前全文（unchanged/modified 时必填）
      "modified_text": "...",        // 修改后全文（unchanged/modified/added 时必填）
      "segments": [                  // 仅 status=modified 时需要，按语义片段拆分
        {"type": "unchanged", "text": "一种方法，包括"},
        {"type": "deleted", "text": "步骤A"},
        {"type": "inserted", "text": "步骤A和步骤B"},
        {"type": "unchanged", "text": "，其特征在于..."}
      ]
    }
  ]
}

注意：
- segments 字段用于精细控制标记粒度。如果不提供 segments，
  脚本会对 original_text 和 modified_text 做简单的整段对比标记。
- 每条 claim 的 status 必须是 "unchanged"/"modified"/"deleted"/"added" 之一。
"""

import json
import sys
from pathlib import Path

from docx import Document
from docx.shared import Pt, RGBColor


def add_deleted(paragraph, text):
    """删除标记：红色 + 删除线"""
    run = paragraph.add_run(text)
    run.font.color.rgb = RGBColor(0xFF, 0x00, 0x00)
    run.font.strike = True
    return run


def add_inserted(paragraph, text):
    """新增标记：红色 + 下划线"""
    run = paragraph.add_run(text)
    run.font.color.rgb = RGBColor(0xFF, 0x00, 0x00)
    run.underline = True
    return run


def add_normal(paragraph, text):
    """正常文本：黑色"""
    run = paragraph.add_run(text)
    return run


def render_claim(paragraph, claim):
    """渲染单条权利要求（含修订标记）"""
    status = claim.get("status", "unchanged")

    if status == "deleted":
        # 整条删除：全部标红+删除线
        orig_num = claim.get("original_number", "")
        orig_text = claim.get("original_text", "")
        add_deleted(paragraph, f"{orig_num}. {orig_text}")
        return

    if status == "added":
        # 整条新增：编号和正文都标红+下划线
        num = claim.get("number", "")
        text = claim.get("modified_text", "")
        add_inserted(paragraph, f"{num}. ")
        add_inserted(paragraph, text)
        return

    if status == "unchanged":
        # 无修改：正常黑色
        num = claim.get("number", "")
        text = claim.get("modified_text", claim.get("original_text", ""))
        add_normal(paragraph, f"{num}. {text}")
        return

    if status == "modified":
        segments = claim.get("segments", [])

        # 编号部分
        orig_num = claim.get("original_number")
        new_num = claim.get("number")
        if orig_num != new_num:
            add_deleted(paragraph, f"{orig_num}.")
            add_inserted(paragraph, f"{new_num}.")
        else:
            add_normal(paragraph, f"{new_num}.")

        # 正文部分
        if segments:
            # 按语义片段逐段标记（精细模式）
            for seg in segments:
                seg_type = seg.get("type", "unchanged")
                seg_text = seg.get("text", "")
                if not seg_text:
                    continue
                if seg_type == "unchanged":
                    add_normal(paragraph, seg_text)
                elif seg_type == "deleted":
                    add_deleted(paragraph, seg_text)
                elif seg_type == "inserted":
                    add_inserted(paragraph, seg_text)
                elif seg_type == "replaced":
                    add_deleted(paragraph, seg.get("old", ""))
                    add_inserted(paragraph, seg.get("new", ""))
        else:
            # 无 segments 时退化为整段对比（粗略模式）
            original = claim.get("original_text", "")
            modified = claim.get("modified_text", "")
            if original and modified and original != modified:
                add_deleted(paragraph, original)
                add_inserted(paragraph, modified)
            elif modified:
                add_normal(paragraph, modified)


def generate_tracked_docx(amendments_path, output_path):
    """主函数：从 JSON 生成带修订标记的 docx"""
    with open(amendments_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    doc = Document()

    # 默认字体
    style = doc.styles["Normal"]
    style.font.name = "宋体"
    style.font.size = Pt(12)

    # 标题
    title = doc.add_heading("权利要求书（修订标记版）", level=1)

    # 逐条渲染
    claims = data.get("claims", [])
    for claim in claims:
        p = doc.add_paragraph()
        render_claim(p, claim)

    doc.save(output_path)
    print(f"OK: {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python generate_tracked_claims.py <amendments.json> <output.docx>")
        sys.exit(1)
    generate_tracked_docx(sys.argv[1], sys.argv[2])
