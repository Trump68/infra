# -*- coding: utf-8 -*-
"""Remove Markdown inline code backticks `...` outside ``` fenced blocks."""
from __future__ import annotations

import re
import sys
from pathlib import Path

INLINE = re.compile(r"`([^`]+)`")


def strip_outside_fences(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    in_fence = False
    for line in lines:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
        else:
            out.append(INLINE.sub(r"\1", line))
    return "".join(out)


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: strip_inline_md_code.py <file.md>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    raw = path.read_text(encoding="utf-8")
    path.write_text(strip_outside_fences(raw), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
