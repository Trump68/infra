# -*- coding: utf-8 -*-
"""Convert Farmadoc DOCX to GitHub-flavored Markdown using Word paragraph styles."""
from __future__ import annotations

import re
import sys
from pathlib import Path

from docx import Document
from docx.document import Document as DocumentObject
from docx.oxml.ns import qn
from docx.oxml.table import CT_Tbl
from docx.oxml.text.paragraph import CT_P
from docx.table import Table, _Cell
from docx.text.paragraph import Paragraph


def iter_block_items(parent: DocumentObject | _Cell):
    if isinstance(parent, DocumentObject):
        parent_elm = parent.element.body
    elif isinstance(parent, _Cell):
        parent_elm = parent._tc
    else:
        raise ValueError(type(parent))
    for child in parent_elm.iterchildren():
        if isinstance(child, CT_P):
            yield Paragraph(child, parent)
        elif isinstance(child, CT_Tbl):
            yield Table(child, parent)


def _list_level(p: Paragraph) -> int | None:
    ppr = p._p.pPr
    if ppr is None or ppr.numPr is None:
        return None
    ilvl = ppr.numPr.find(qn("w:ilvl"))
    if ilvl is None:
        return 0
    v = ilvl.get(qn("w:val"))
    return int(v) if v is not None else 0


def _escape_cell(text: str) -> str:
    return text.replace("\n", " ").replace("|", "\\|").strip()


def table_to_md(table: Table) -> str:
    rows = []
    for row in table.rows:
        cells = [_escape_cell(c.text) for c in row.cells]
        rows.append(cells)
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    norm = [r + [""] * (width - len(r)) for r in rows]
    lines = []
    header = norm[0]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("| " + " | ".join("---" for _ in header) + " |")
    for r in norm[1:]:
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines) + "\n\n"


def runs_to_md(p: Paragraph) -> str:
    parts: list[str] = []
    for r in p.runs:
        t = r.text.replace("\r", "")
        if not t:
            continue
        if r.bold and r.italic:
            t = f"***{t}***"
        elif r.bold:
            t = f"**{t}**"
        elif r.italic:
            t = f"*{t}*"
        parts.append(t)
    return "".join(parts).strip()


def paragraph_to_md(p: Paragraph) -> str | None:
    text = runs_to_md(p)
    style = (p.style and p.style.name) or "Normal"

    if style == "Heading 1":
        return f"# {text}\n\n" if text else None
    if style == "Heading 2":
        return f"## {text}\n\n" if text else None
    if style == "Heading 3":
        return f"### {text}\n\n" if text else None
    if style == "Heading 4":
        return f"#### {text}\n\n" if text else None

    if style == "List Paragraph":
        lvl = _list_level(p)
        # Word often uses outline level 1 for top-level bullets.
        md_depth = max(0, (lvl if lvl is not None else 1) - 1)
        indent = "  " * md_depth
        if not text:
            return None
        line = f"{indent}- {text}\n"
        return line

    # Normal and everything else
    if not text:
        return "\n"
    return text + "\n\n"


def cell_to_md(cell: _Cell) -> str:
    out: list[str] = []
    for block in iter_block_items(cell):
        if isinstance(block, Paragraph):
            md = paragraph_to_md(block)
            if md:
                out.append(md.rstrip("\n"))
        else:
            out.append(table_to_md(block).rstrip("\n"))
    return "\n".join(s for s in out if s).strip()


def convert(docx_path: Path, md_path: Path) -> None:
    doc = Document(docx_path)
    chunks: list[str] = []
    for block in iter_block_items(doc):
        if isinstance(block, Paragraph):
            piece = paragraph_to_md(block)
            if piece is not None:
                chunks.append(piece)
        else:
            chunks.append(table_to_md(block))

    raw = "".join(chunks)
    raw = re.sub(r"\n{4,}", "\n\n\n", raw)
    raw = raw.strip() + "\n"
    md_path.write_text(raw, encoding="utf-8")


def main() -> int:
    base = Path(__file__).resolve().parent.parent / "Farmadoc_documentation"
    docx = base / "1.Пояснительная записка к техническому проекту.docx"
    out = base / "1.Пояснительная записка к техническому проекту-copy.md"
    if not docx.is_file():
        print("DOCX not found:", docx, file=sys.stderr)
        return 1
    convert(docx, out)
    print("Written", out, "size", out.stat().st_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
