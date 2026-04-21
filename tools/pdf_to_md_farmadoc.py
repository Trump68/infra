# -*- coding: utf-8 -*-
"""One-off: PDF -> Markdown via PyMuPDF text extraction."""
import sys
from pathlib import Path

import fitz  # PyMuPDF


def main() -> int:
    base = Path(__file__).resolve().parent.parent / "Farmadoc_documentation"
    pdf_name = "1.Пояснительная записка к техническому проекту-PDF.pdf"
    out_name = "1.Пояснительная записка к техническому проекту-from-PDF.md"
    pdf_path = base / pdf_name
    out_path = base / out_name

    if not pdf_path.is_file():
        print("PDF not found:", pdf_path, file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)
    parts: list[str] = [
        f"# {pdf_name.replace('-PDF.pdf', '')}\n\n",
        f"_Автоматически извлечено из PDF ({pdf_path.name}), {len(doc)} стр. "
        "Без сохранения исходной вёрстки и оглавления._\n\n",
        "---\n\n",
    ]

    for i in range(len(doc)):
        page = doc[i]
        text = page.get_text("text")
        parts.append(f"## Страница {i + 1}\n\n")
        parts.append(text.strip() or "_[пустая страница]_\n")
        parts.append("\n\n")

    doc.close()
    out_path.write_text("".join(parts), encoding="utf-8")
    print("Wrote", out_path, "chars", out_path.stat().st_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
