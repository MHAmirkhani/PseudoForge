#!/usr/bin/env python3
"""check-anchors.py -- verify every [text](file.md#anchor) link resolves.

The test suite already checks that the *file* of a relative link exists.
It does not check the anchor: a link to `limitations.md#--projector` is
just as broken as one to a missing file, and the reader who follows it
lands at the top of the page with no idea what went wrong.

Anchors are the slugs MkDocs builds from the headings.  This script
computes the same slugs (GitHub-flavoured: lower-case, punctuation
stripped, spaces to hyphens) and reports every link whose anchor is not
among them.

Usage:
  tools/check-anchors.py           # scan docs/, exit 1 if broken
  tools/check-anchors.py --list    # also print all heading slugs

Kept in Python because slugification is regex over Unicode and doing it
in awk would be a paragraph of escapes for no gain.  Same reason the
server is Python: an external tool, documented as such.
"""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DOCS = ROOT / "docs"


def slugify(text: str) -> str:
    """The MkDocs heading slug.

    This is Python-Markdown's toc extension, which is what MkDocs uses,
    and not GitHub's variant.  The two differ in three ways that all
    show up in this project's headings:

      * runs of whitespace *and* hyphens collapse to a single hyphen,
        so `The --projector flag` slugs as `the-projector-flag`, not
        `the---projector-flag`;
      * leading and trailing hyphens are kept, so `--projector` slugs
        as `-projector`, not `projector`;
      * a heading that slugs to a value already on the page gets `_1`,
        `_2` appended -- handled in `collect_slugs`, below.

    NFKD-normalise, drop accents, lower-case, strip everything that is
    not a word character, whitespace or hyphen, strip whitespace, then
    collapse `[-\\s]+` to a single hyphen.
    """
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^\w\s-]", "", text.lower()).strip()
    return re.sub(r"[-\s]+", "-", text)


def collect_slugs() -> dict[Path, set[str]]:
    """Every heading slug, per page.

    Duplicate headings get `_1`, `_2` ... appended the way
    Python-Markdown's toc extension does.  A page with two `Notes`
    headings has anchors `notes` and `notes_1`; a link to `#notes_1` is
    valid and a link to `#notes_2` on that page is not.
    """
    slugs: dict[Path, set[str]] = {}
    for md in DOCS.rglob("*.md"):
        headings = re.findall(r"^#{1,6}\s+(.+)$", md.read_text(encoding="utf-8"), re.MULTILINE)
        page: set[str] = set()
        seen: dict[str, int] = {}
        for h in headings:
            base = slugify(h)
            n = seen.get(base, 0)
            seen[base] = n + 1
            page.add(base if n == 0 else f"{base}_{n}")
        slugs[md.relative_to(DOCS)] = page
    return slugs


LINK_RE = re.compile(r"\[[^\]]+\]\(([^)\s]+\.md#[^)\s]+)\)")


def main(argv: list[str]) -> int:
    if not DOCS.is_dir():
        print(f"no docs/ directory at {DOCS}", file=sys.stderr)
        return 1

    slugs = collect_slugs()

    if "--list" in argv:
        for rel, anchors in sorted(slugs.items()):
            print(f"\n{rel}")
            for a in sorted(anchors):
                print(f"  #{a}")

    problems: list[tuple[Path, str, str]] = []
    for md in DOCS.rglob("*.md"):
        rel_md = md.relative_to(DOCS)
        for m in LINK_RE.finditer(md.read_text(encoding="utf-8")):
            target = m.group(1)
            path_part, anchor = target.split("#", 1)
            if path_part.startswith("/"):
                rel = Path(path_part.lstrip("/"))
            else:
                rel = (md.parent / path_part).resolve().relative_to(DOCS)
            if rel not in slugs:
                problems.append((rel_md, target, "target file not found"))
            elif anchor not in slugs[rel]:
                problems.append((rel_md, target, f"anchor not present in {rel}"))

    if problems:
        for src, target, why in problems:
            print(f"{src}")
            print(f"  -> {target}")
            print(f"     {why}")
        print(f"\n{len(problems)} broken anchor link(s)")
        return 1

    print("all internal anchors resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
