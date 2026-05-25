import logging
import os
import tempfile
from pathlib import Path

logger = logging.getLogger("plugin.document-processor")

_MAX_PAGES = 30
_PAGE_RENDER_DPI = 150
_MAX_IMAGE_SIZE = 5 * 1024 * 1024

_NO_RE_READ_INSTRUCTION = (
    "[System: The following is the complete extracted content of the uploaded document. "
    "All text and images have already been fully extracted and are provided below. "
    "Do NOT attempt to read, download, or re-process the original file. "
    "Just answer the user's question directly based on the content below.]"
)


def _extract_pdf(file_path: str) -> dict:
    try:
        import fitz
    except ImportError:
        logger.warning("pymupdf not installed, skipping PDF extraction")
        return {}

    text_parts: list[str] = []
    image_files: list[tuple[str, str]] = []
    try:
        doc = fitz.open(file_path)
        page_count = min(len(doc), _MAX_PAGES)
        tmp_dir = tempfile.mkdtemp(prefix="hermes_doc_")

        for i in range(page_count):
            page = doc[i]
            text = page.get_text("text").strip()
            if text:
                text_parts.append(f"--- Page {i + 1} ---\n{text}")

            pix = page.get_pixmap(dpi=_PAGE_RENDER_DPI)
            img_bytes = pix.tobytes("png")
            if len(img_bytes) <= _MAX_IMAGE_SIZE:
                img_path = os.path.join(tmp_dir, f"page_{i + 1}.png")
                with open(img_path, "wb") as f:
                    f.write(img_bytes)
                image_files.append((img_path, "image/png"))

        doc.close()
    except Exception:
        logger.warning("PDF extraction failed for %s", file_path, exc_info=True)
        return {}

    if not text_parts and not image_files:
        return {}

    filename = Path(file_path).name
    header = f"[Document: {filename} (PDF, {page_count} pages)]"
    combined_text = header + "\n\n" + "\n\n".join(text_parts) if text_parts else header

    # Append page image paths into text (gateway rewrite only forwards text, not media_urls)
    if image_files:
        img_list = "\n".join(f"- {path}" for path, _ in image_files)
        combined_text += f"\n\n[Page images ({len(image_files)} files), use vision_analyze to read:\n{img_list}]"

    return {"text": combined_text}


def _extract_docx(file_path: str) -> dict:
    try:
        from docx import Document
    except ImportError:
        logger.warning("python-docx not installed, skipping docx extraction")
        return {}

    text_parts: list[str] = []
    image_files: list[tuple[str, str]] = []
    try:
        doc = Document(file_path)

        for para in doc.paragraphs:
            text = para.text.strip()
            if text:
                text_parts.append(text)

        for table in doc.tables:
            table_lines: list[str] = []
            for row in table.rows:
                cells = [cell.text.strip() for cell in row.cells]
                table_lines.append(" | ".join(cells))
            if table_lines:
                text_parts.append("--- Table ---\n" + "\n".join(table_lines))

        tmp_dir = tempfile.mkdtemp(prefix="hermes_doc_")
        image_index = 0
        for rel in doc.part.rels.values():
            if "image" in rel.reltype:
                try:
                    image_data = rel.target_part.blob
                    if len(image_data) <= _MAX_IMAGE_SIZE:
                        image_index += 1
                        ext = ".png"
                        content_type = rel.target_part.content_type or "image/png"
                        if "jpeg" in content_type or "jpg" in content_type:
                            ext = ".jpg"
                        elif "gif" in content_type:
                            ext = ".gif"
                        elif "bmp" in content_type:
                            ext = ".bmp"
                        img_path = os.path.join(tmp_dir, f"embedded_{image_index}{ext}")
                        with open(img_path, "wb") as f:
                            f.write(image_data)
                        image_files.append((img_path, content_type))
                        text_parts.append(f"[Embedded image {image_index}]")
                except Exception:
                    pass

    except Exception:
        logger.warning("docx extraction failed for %s", file_path, exc_info=True)
        return {}

    if not text_parts and not image_files:
        return {}

    filename = Path(file_path).name
    combined_text = f"[Document: {filename} (docx)]\n\n" + "\n\n".join(text_parts)

    # Append embedded image paths into text (gateway rewrite only forwards text, not media_urls)
    if image_files:
        img_list = "\n".join(f"- {path}" for path, _ in image_files)
        combined_text += f"\n\n[Embedded images ({len(image_files)} files), use vision_analyze to read:\n{img_list}]"

    return {"text": combined_text}


def _process_document(file_path: str, media_type: str) -> dict:
    ext = Path(file_path).suffix.lower()
    if ext == ".pdf" or media_type == "application/pdf":
        return _extract_pdf(file_path)
    if ext in {".docx", ".doc"} or media_type in {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/msword",
    }:
        return _extract_docx(file_path)
    return {}


def pre_gateway_dispatch(event, gateway=None, session_store=None, **kwargs):
    from gateway.platforms.base import MessageType

    if event.message_type != MessageType.DOCUMENT:
        return None

    media_urls = getattr(event, "media_urls", None) or []
    media_types = getattr(event, "media_types", None) or []

    if not media_urls:
        return None

    all_text_parts: list[str] = []

    for path, mtype in zip(media_urls, media_types):
        result = _process_document(path, mtype)
        if not result:
            continue
        if result.get("text"):
            all_text_parts.append(result["text"])

    if not all_text_parts:
        return None

    original_text = event.text or ""
    combined = "\n\n".join(all_text_parts)
    if original_text.strip():
        new_text = f"{original_text}\n\n{_NO_RE_READ_INSTRUCTION}\n\n{combined}"
    else:
        new_text = f"{_NO_RE_READ_INSTRUCTION}\n\n{combined}"

    logger.info(
        "document-processor: rewrote document (%d chars)",
        len(new_text),
    )
    return {"action": "rewrite", "text": new_text}


def register(ctx) -> None:
    ctx.register_hook("pre_gateway_dispatch", pre_gateway_dispatch)
    logger.info("document-processor plugin registered")
