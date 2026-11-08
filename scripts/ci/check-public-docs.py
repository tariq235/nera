#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Every public/open declaration in Packages/*/Sources must have a /// doc comment (API design rule 5).

Attributes (@MainActor, @discardableResult, …) may sit between the comment and the declaration.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DECL = re.compile(r"^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:public|open)\s+(?!import\b)")
ATTRIBUTE = re.compile(r"^\s*@[\w.]+(?:\([^)]*\))?\s*$")


def main() -> int:
    missing = []
    total = 0
    for f in sorted(ROOT.glob("Packages/*/Sources/**/*.swift")):
        lines = f.read_text().splitlines()
        for i, line in enumerate(lines):
            if not DECL.match(line):
                continue
            total += 1
            j = i - 1
            while j >= 0 and ATTRIBUTE.match(lines[j]):
                j -= 1
            prev = lines[j].strip() if j >= 0 else ""
            if not (prev.startswith("///") or prev.endswith("*/")):
                missing.append(f"{f.relative_to(ROOT)}:{i + 1}: {line.strip()[:90]}")
    for m in missing:
        print(f"✘ undocumented public API: {m}", file=sys.stderr)
    if missing:
        return 1
    print(f"✔ public API documented ({total} declarations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
