#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Fail if any Markdown file links to a repo file or #anchor that doesn't exist.

Checks relative links only (external URLs are checked by lychee in CI).
Anchors use GitHub's heading slug rules.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP_DIRS = {".git", "build", "tools", ".build", "node_modules"}
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^#{1,6}\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")


def slug(heading: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # [text](url) -> text
    text = re.sub(r"[`*]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    seen: dict[str, int] = {}
    out: set[str] = set()
    in_fence = False
    for line in path.read_text(errors="ignore").splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if m := HEADING.match(line):
            s = slug(m.group(1))
            n = seen.get(s, 0)
            out.add(s if n == 0 else f"{s}-{n}")
            seen[s] = n + 1
    return out


def markdown_files() -> list[Path]:
    # scripts/release/public, where it exists, holds files prepared for another tree; their links are checked there.
    return [p for p in ROOT.rglob("*.md")
            if not SKIP_DIRS & set(p.relative_to(ROOT).parts) and not str(p.relative_to(ROOT)).startswith("scripts/release/public/")]


def main() -> int:
    errors = []
    cache: dict[Path, set[str]] = {}
    for md in markdown_files():
        in_fence = False
        for lineno, line in enumerate(md.read_text(errors="ignore").splitlines(), 1):
            if FENCE.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target):  # http:, mailto:, …
                    continue
                path_part, _, anchor = target.partition("#")
                dest = (md.parent / path_part).resolve() if path_part else md
                where = f"{md.relative_to(ROOT)}:{lineno}"
                if not dest.exists():
                    errors.append(f"{where}: broken link → {target}")
                    continue
                if anchor and dest.suffix == ".md":
                    cache.setdefault(dest, anchors(dest))
                    if anchor not in cache[dest]:
                        errors.append(f"{where}: missing anchor → {target}")
    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"✔ doc links OK ({len(markdown_files())} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
