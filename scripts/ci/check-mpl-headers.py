#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Every source file carries the MPL-2.0 header (ADR-0005). `--fix` adds it where missing (after a shebang line).
Covers every published source file: Swift, Objective-C/C/C++, JavaScript, Python and shell in the app, packages,
tests, fixtures and scripts. The header must be at the
top (after a shebang or `swift-tools-version` line)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARK = "Mozilla Public License, v. 2.0"
SLASH = {".swift", ".h", ".m", ".mm", ".c", ".cc", ".cpp", ".js"}
HASH = {".py", ".sh"}
SCOPE = ("Apps/", "Packages/", "UITests/", "Tests/", "scripts/")
TEXT = (
    "This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was",
    "not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.",
)


def header(suffix: str) -> str:
    prefix = "// " if suffix in SLASH else "# "
    return "".join(prefix + line + "\n" for line in TEXT)


def files() -> list[Path]:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, text=True, check=True).stdout
    tracked = [f for f in out.split("\0") if f]
    return [ROOT / f for f in tracked if f.startswith(SCOPE) and Path(f).suffix in SLASH | HASH]


def add_header(f: Path) -> None:
    text = f.read_text()
    lines = text.splitlines(keepends=True)
    if lines and (lines[0].startswith("#!") or lines[0].startswith("// swift-tools-version")):
        f.write_text(lines[0] + header(f.suffix) + "".join(lines[1:]))
    else:
        f.write_text(header(f.suffix) + ("\n" if f.suffix in SLASH else "") + text)


def has_header(f: Path) -> bool:
    """The mark within the first few lines (a shebang or tools-version line may come first)."""
    head = f.read_text(errors="ignore").splitlines()[:5]
    return any(MARK in line for line in head)


def main() -> int:
    fix = "--fix" in sys.argv
    sources = files()
    missing = [f for f in sources if not has_header(f)]
    if fix:
        for f in missing:
            add_header(f)
        missing = []
    for f in missing:
        print(f"✘ {f.relative_to(ROOT)}: missing the MPL-2.0 header (scripts/ci/check-mpl-headers.py --fix)", file=sys.stderr)
    if missing:
        return 1
    print(f"✔ MPL-2.0 headers on all {len(sources)} source files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
