#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Log redaction gate (PRV-007, SEC-070).

Shipped code must never log URLs, titles, cookies, tokens or passwords:
- no print / NSLog / debugPrint / dump in Swift (use NeraLog or os.Logger, whose dynamic values are private);
- `privacy: .public` only for `Redact.*` values (scheme-only URLs, error domain#code);
- Objective-C++ NSLog only with numeric arguments (no %@ / %s).
Debug-only files that print test results carry `// log-check: debug-only` and are skipped.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCOPE = ["Packages/NeraKit/Sources", "Apps"]
PRINT = re.compile(r"(?<![\w.])(print|NSLog|debugPrint|dump)\s*\(")
OBJC_NSLOG = re.compile(r"NSLog\(@\"[^\"]*%[@s]")


def strip_comments(line: str) -> str:
    return line.split("//", 1)[0] if "//" in line and not re.search(r'"[^"]*//[^"]*"', line) else line


def main() -> int:
    errors: list[str] = []
    for base in SCOPE:
        for f in (ROOT / base).rglob("*"):
            if f.suffix not in {".swift", ".mm", ".m"} or "/.build/" in str(f):
                continue
            text = f.read_text(errors="ignore")
            if "log-check: debug-only" in text:
                continue
            rel = f.relative_to(ROOT)
            for n, raw in enumerate(text.splitlines(), 1):
                line = strip_comments(raw)
                if f.suffix == ".swift":
                    if PRINT.search(line):
                        errors.append(f"{rel}:{n}: use NeraLog/os.Logger, not print/NSLog (PRV-007)")
                    for m in re.finditer(r"privacy:\s*\.public", line):
                        start = line.rfind("\\(", 0, m.start())  # the interpolation this belongs to
                        expr = line[start + 2:m.start()].strip() if start >= 0 else ""
                        if not expr.startswith("Redact."):
                            errors.append(f"{rel}:{n}: only Redact.* values may be logged as .public: {expr[:60]}")
                elif OBJC_NSLOG.search(line):
                    errors.append(f"{rel}:{n}: NSLog with %@/%s can leak URLs; log numbers only (PRV-007)")
    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    print("✔ log redaction OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
