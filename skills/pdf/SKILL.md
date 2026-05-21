---
name: pdf
description: Comprehensive PDF manipulation toolkit for extracting text and tables, creating new PDFs, merging/splitting documents, and handling forms. When Claude needs to fill in a PDF form or programmatically process, generate, or analyze PDF documents at scale.
license: Proprietary. LICENSE.txt has complete terms
---

# PDF Processing Guide

## Overview

This guide covers essential PDF processing operations using Python libraries and command-line tools. For advanced features, JavaScript libraries, and detailed examples, see reference.md. If you need to fill out a PDF form, read forms.md and follow its instructions.

## Quick Start

```python
from pypdf import PdfReader, PdfWriter

# Read a PDF
reader = PdfReader("document.pdf")
print(f"Pages: {len(reader.pages)}")

# Extract text
text = ""
for page in reader.pages:
    text += page.extract_text()
```

## Python Libraries

### pypdf - Basic Operations

#### Merge PDFs
```python
from pypdf import PdfWriter, PdfReader

writer = PdfWriter()
for pdf_file in ["doc1.pdf", "doc2.pdf", "doc3.pdf"]:
    reader = PdfReader(pdf_file)
    for page in reader.pages:
        writer.add_page(page)

with open("merged.pdf", "wb") as output:
    writer.write(output)
```

#### Split PDF
```python
reader = PdfReader("input.pdf")
for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    with open(f"page_{i+1}.pdf", "wb") as output:
        writer.write(output)
```

#### Extract Metadata
```python
reader = PdfReader("document.pdf")
meta = reader.metadata
print(f"Title: {meta.title}")
print(f"Author: {meta.author}")
print(f"Subject: {meta.subject}")
print(f"Creator: {meta.creator}")
```

#### Rotate Pages
```python
reader = PdfReader("input.pdf")
writer = PdfWriter()

page = reader.pages[0]
page.rotate(90)  # Rotate 90 degrees clockwise
writer.add_page(page)

with open("rotated.pdf", "wb") as output:
    writer.write(output)
```

### pdfplumber - Text and Table Extraction

#### Extract Text with Layout
```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        print(text)
```

#### Extract Tables
```python
with pdfplumber.open("document.pdf") as pdf:
    for i, page in enumerate(pdf.pages):
        tables = page.extract_tables()
        for j, table in enumerate(tables):
            print(f"Table {j+1} on page {i+1}:")
            for row in table:
                print(row)
```

#### Advanced Table Extraction
```python
import pandas as pd

with pdfplumber.open("document.pdf") as pdf:
    all_tables = []
    for page in pdf.pages:
        tables = page.extract_tables()
        for table in tables:
            if table:  # Check if table is not empty
                df = pd.DataFrame(table[1:], columns=table[0])
                all_tables.append(df)

# Combine all tables
if all_tables:
    combined_df = pd.concat(all_tables, ignore_index=True)
    combined_df.to_excel("extracted_tables.xlsx", index=False)
```

### reportlab - Create PDFs

#### Basic PDF Creation
```python
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

c = canvas.Canvas("hello.pdf", pagesize=letter)
width, height = letter

# Add text
c.drawString(100, height - 100, "Hello World!")
c.drawString(100, height - 120, "This is a PDF created with reportlab")

# Add a line
c.line(100, height - 140, 400, height - 140)

# Save
c.save()
```

#### Create PDF with Multiple Pages
```python
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet

doc = SimpleDocTemplate("report.pdf", pagesize=letter)
styles = getSampleStyleSheet()
story = []

# Add content
title = Paragraph("Report Title", styles['Title'])
story.append(title)
story.append(Spacer(1, 12))

body = Paragraph("This is the body of the report. " * 20, styles['Normal'])
story.append(body)
story.append(PageBreak())

# Page 2
story.append(Paragraph("Page 2", styles['Heading1']))
story.append(Paragraph("Content for page 2", styles['Normal']))

# Build PDF
doc.build(story)
```

## Command-Line Tools

### pdftotext (poppler-utils)
```bash
# Extract text
pdftotext input.pdf output.txt

# Extract text preserving layout
pdftotext -layout input.pdf output.txt

# Extract specific pages
pdftotext -f 1 -l 5 input.pdf output.txt  # Pages 1-5
```

### qpdf
```bash
# Merge PDFs
qpdf --empty --pages file1.pdf file2.pdf -- merged.pdf

# Split pages
qpdf input.pdf --pages . 1-5 -- pages1-5.pdf
qpdf input.pdf --pages . 6-10 -- pages6-10.pdf

# Rotate pages
qpdf input.pdf output.pdf --rotate=+90:1  # Rotate page 1 by 90 degrees

# Remove password
qpdf --password=mypassword --decrypt encrypted.pdf decrypted.pdf
```

### pdftk (if available)
```bash
# Merge
pdftk file1.pdf file2.pdf cat output merged.pdf

# Split
pdftk input.pdf burst

# Rotate
pdftk input.pdf rotate 1east output rotated.pdf
```

## Common Tasks

### Extract Text from Scanned PDFs
```python
# Requires: pip install pytesseract pdf2image
import pytesseract
from pdf2image import convert_from_path

# Convert PDF to images
images = convert_from_path('scanned.pdf')

# OCR each page
text = ""
for i, image in enumerate(images):
    text += f"Page {i+1}:\n"
    text += pytesseract.image_to_string(image)
    text += "\n\n"

print(text)
```

### Add Watermark
```python
from pypdf import PdfReader, PdfWriter

# Create watermark (or load existing)
watermark = PdfReader("watermark.pdf").pages[0]

# Apply to all pages
reader = PdfReader("document.pdf")
writer = PdfWriter()

for page in reader.pages:
    page.merge_page(watermark)
    writer.add_page(page)

with open("watermarked.pdf", "wb") as output:
    writer.write(output)
```

### Extract Images
```bash
# Using pdfimages (poppler-utils)
pdfimages -j input.pdf output_prefix

# This extracts all images as output_prefix-000.jpg, output_prefix-001.jpg, etc.
```

### Password Protection
```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
writer = PdfWriter()

for page in reader.pages:
    writer.add_page(page)

# Add password
writer.encrypt("userpassword", "ownerpassword")

with open("encrypted.pdf", "wb") as output:
    writer.write(output)
```

## Quick Reference

| Task | Best Tool | Command/Code |
|------|-----------|--------------|
| Merge PDFs | pypdf | `writer.add_page(page)` |
| Split PDFs | pypdf | One page per file |
| Extract text | pdfplumber | `page.extract_text()` |
| Extract tables | pdfplumber | `page.extract_tables()` |
| Create PDFs | reportlab | Canvas or Platypus |
| Command line merge | qpdf | `qpdf --empty --pages ...` |
| OCR scanned PDFs | pytesseract | Convert to image first |
| Fill PDF forms | pdf-lib or pypdf (see forms.md) | See forms.md |

## Creating PDFs from Markdown with Pandoc

### Overview

For academic papers, technical documentation, or any document with **mathematical formulas**, the best approach is to use **Pandoc** to convert Markdown directly to PDF. This method:

- ✅ Perfectly supports LaTeX mathematical formulas
- ✅ Handles Chinese characters with XeLaTeX
- ✅ Generates professional table of contents
- ✅ Industry standard for academic publishing

### Simple PDF Generation Workflow

**Follow this workflow to generate PDF files:**

1. **Create Markdown file** in `/workspace/my-workspace/generated_docs/`
2. **Run pandoc command** to convert to PDF
3. **Download via existing API** - `GET /api/projects/:projectName/file/download?filePath=...`

**Step 1: Create Markdown**
```bash
cat > /workspace/my-workspace/generated_docs/document.md << 'EOF'
# Document Title

## Section 1

Content with **bold** and *italic* text.

### Mathematical Formula

The mass-energy equivalence equation:
$$E = mc^2$$

Trigonometric identity:
$$\sin^2\alpha + \cos^2\alpha = 1$$

## Section 2

| Column 1 | Column 2 |
|----------|----------|
| Data 1   | Data 2   |
EOF
```

**Step 2: Convert to PDF with Pandoc**
```bash
# Recommended command for Chinese documents
pandoc /workspace/my-workspace/generated_docs/document.md \
  -o /workspace/my-workspace/generated_docs/document.pdf \
  --pdf-engine=xelatex \
  -V CJKmainfont="Noto Sans CJK SC" \
  --toc \
  --toc-depth=2 \
  --number-sections
```

**Step 3: Download**
- The PDF file is saved at: `/workspace/my-workspace/generated_docs/document.pdf`
- Use the existing `downloadFile` API to download
- No special API endpoint needed - PDF files work like any other file

### Markdown to PDF Conversion

```bash
# Basic conversion
pandoc input.md -o output.pdf

# With XeLaTeX engine (for Chinese and formulas)
pandoc input.md -o output.pdf --pdf-engine=xelatex

# With table of contents
pandoc input.md -o output.pdf --pdf-engine=xelatex --toc

# Full options (recommended for Chinese documents)
pandoc input.md -o output.pdf \
  --pdf-engine=xelatex \
  -V CJKmainfont="Noto Sans CJK SC" \
  --toc \
  --toc-depth=3 \
  --number-sections
```

### Mathematical Formula Format

When creating PDFs with formulas, **ALWAYS use LaTeX format**:

✅ **USE LaTeX format**:
```markdown
Inline formula: $E = mc^2$

Block formula:
$$\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}$$

Matrix:
$$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$
```

**LaTeX Formula Examples**:

| Description | LaTeX | Result |
|-------------|-------|--------|
| Superscript | `$x^2$` | x² |
| Subscript | `$H_2O$` | H₂O |
| Greek letters | `$\alpha, \beta, \pi$` | α, β, π |
| Fractions | `$\frac{a}{b}$` | a/b |
| Square root | `$\sqrt{x}$` | √x |
| Summation | `$\sum_{i=1}^n$` | Σᵢ₌₁ⁿ |
| Integral | `$\int_0^\infty$` | ∫₀^∞ |
| Matrix | `$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$` | matrix |

### Example Markdown Document

```markdown
---
title: "Technical Report"
author: "Author Name"
---

# Introduction

This document demonstrates PDF generation with **mathematical formulas**.

## Mathematical Formulas

The famous equation:
$$E = mc^2$$

Trigonometric identity:
$$\sin^2\alpha + \cos^2\alpha = 1$$

## Conclusion

This concludes the example.
```

### Supported Chinese Fonts (in Container)

**Available in sandbox container:**
- `Noto Sans CJK SC` - 思源黑体 (DEFAULT - use this)
- `Noto Serif CJK SC` - 思源宋体

**Common fonts (may not be available in container):**
- `SimSun` - 宋体
- `SimHei` - 黑体
- `FangSong` - 仿宋
- `KaiTi` - 楷体
- `Microsoft YaHei` - 微软雅黑

**Note**: Always use `Noto Sans CJK SC` in the container environment as it's the only guaranteed available Chinese font.

## Next Steps

- For advanced pypdfium2 usage, see reference.md
- For JavaScript libraries (pdf-lib), see reference.md
- If you need to fill out a PDF form, follow the instructions in forms.md
- For troubleshooting guides, see reference.md
