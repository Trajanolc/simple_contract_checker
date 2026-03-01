import io

import pdfplumber
from docx import Document

from core.config import settings


def extract_text(content: bytes, filename: str) -> str:
    lower = filename.lower()
    if lower.endswith(".pdf"):
        with pdfplumber.open(io.BytesIO(content)) as pdf:
            text = "\n".join(page.extract_text() or "" for page in pdf.pages)
    elif lower.endswith(".docx"):
        doc = Document(io.BytesIO(content))
        text = "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    elif lower.endswith(".txt"):
        text = content.decode("utf-8", errors="replace")
    else:
        raise ValueError("Unsupported file type. Supported: .pdf, .docx, .txt")

    return text[: settings.max_doc_chars]
