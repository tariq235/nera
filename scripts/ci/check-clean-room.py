#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Clean-room and naming guards (CLEAN_ROOM.md, ADR-0001, checklist 011).

  check-clean-room.py --rules clean-room   Arc/Dia identifiers + byte-identical Arc assets
  check-clean-room.py --rules naming       Arc product/feature names in user-facing text
  check-clean-room.py                      both

Scope: everything that ships or builds the product: Packages/*/Sources, Apps, UITests, project.yml.

The Arc importer legitimately reads Arc's file format, so `Sources/Import` and its tests may use the
format's names. A line elsewhere that must name Arc (e.g. "Import from Arc…") carries an explicit
`// naming: import-reference` marker, which leaves a reviewable trail.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCOPE = ["Packages/NeraKit/Sources", "Packages/NeraKit/Tests", "Apps", "UITests", "scripts/engine"]
EXTRA_FILES = ["project.yml"]
IMPORTER = ("Packages/NeraKit/Sources/Import/", "Packages/NeraKit/Tests/ImportTests/")
MARKER = "naming: import-reference"
HASHES = ROOT / "scripts" / "ci" / "data" / "arc-asset-hashes.txt"
TEXT = {".swift", ".h", ".m", ".mm", ".plist", ".strings", ".stringsdict", ".yml", ".yaml", ".json", ".html", ".css", ".js", ".md"}

# Identifiers that would indicate copied Arc/Dia code, configuration or infrastructure.
CLEAN_ROOM = [
    (r"company\.thebrowser|thebrowser\.company|The Browser Company", "The Browser Company identifier"),
    (r"S6N382Y83G", "Arc's Apple team ID"),
    (r"\b(?:releases|resources|content|start)\.arc\.net\b|iCloud\.net\.arc|diabrowser\.com|browserinternal\.com", "Arc/Dia endpoint"),
]
# Known identifiers that would only appear in copied code. Stored as SHA-256 digests so this script doesn't spell
# them out; every identifier in a scanned file is hashed and compared (CLEAN_ROOM.md).
INTERNAL_NAME_HASHES = {
    "2a2ce5037de747e014e15e9c89612b4f7450f55ea996b02ff1f68ba6b896013a",
    "3121f19cc46103337b7686a3822b2a097b0549c539be7efef6ba3d88cd05c827",
    "40269935e1a2a5c2785f737f79140ba75c8496603492466572a2631474df1226",
    "4423ceba99eceeade42426dfe68c64a0540fa3fd1d83b3e400f4875ca9707995",
    "68c879051a773b1579e60f344e5d579b3b963fb04d046072d333d5d6f62e8ac4",
    "78f758df86e2abeda64a2ea0fee54afa1d7737949537dc7e4d1be4eecb9a7d43",
    "a5b5e1da45065bae8d53e613e64930faf0bf6861ce785e91808c103e0d89c880",
    "d7b12914caf6fba3a8f92e4e27bc08a6289ab2cf350fe18a5f8d915180140015",
    "f9424675ae778dc66e35f5b30cde6ce10bb2f20ea205a52e29483bdc46589484",
}
INTERNAL_PREFIX_HASHES = {"f12656056eebe51f1da32c7f57f80c141b201a8a0c6039577de86f5c0a9c7c03"}  # 4-character prefix of build metadata keys
IDENTIFIER = re.compile(r"\b[A-Za-z][A-Za-z0-9]+\b")


def internal_name(line: str) -> str | None:
    for token in IDENTIFIER.findall(line):
        if hashlib.sha256(token.encode()).hexdigest() in INTERNAL_NAME_HASHES:
            return token
        if len(token) > 4 and hashlib.sha256(token[:4].encode()).hexdigest() in INTERNAL_PREFIX_HASHES:
            return token
    return None

IMPORTER_ONLY = [
    (r"\bStorable(?:Sidebar|Windows|Archive)\w*", "Arc data-file name outside the importer"),
]
# User-facing Arc product/feature names (trademark / trade dress). Generic words (Spaces, Peek) are fine.
NAMING = [
    (r"\bLittle Arc\b|\bArc (?:Search|Max|Browser|Sync|Member)\b|\bBoosts?\b(?! *=)|\bEasels?\b|\bThe Browser Company\b|\bDia\b",
     "Arc/Dia product or feature name in user-facing text"),
]
PRODUCT_KEYS = re.compile(r"^\s*(PRODUCT_NAME|CFBundleName|CFBundleDisplayName)\s*:\s*(.+)$", re.M)
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')
ARC_WORD = re.compile(r"\bArc\b")


def files() -> list[Path]:
    out = [ROOT / f for f in EXTRA_FILES if (ROOT / f).exists()]
    for base in SCOPE:
        # build/ holds generated output (e.g. the downloaded CEF), never committed.
        out += [p for p in (ROOT / base).rglob("*") if p.is_file() and "/.build/" not in str(p) and "/build/" not in str(p)]
    return out


def clean_room(errors: list[str]) -> None:
    denied = {line.strip() for line in HASHES.read_text().splitlines() if line.strip() and not line.startswith("#")}
    for f in files():
        rel = str(f.relative_to(ROOT))
        if hashlib.sha256(f.read_bytes()).hexdigest() in denied:
            errors.append(f"{rel}: byte-identical to a file in Arc.app (copied asset)")
            continue
        if f.suffix not in TEXT:
            continue
        for n, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
            for pattern, why in CLEAN_ROOM:
                if re.search(pattern, line):
                    errors.append(f"{rel}:{n}: {why}: {line.strip()[:100]}")
            if (token := internal_name(line)) is not None:
                errors.append(f"{rel}:{n}: Arc internal identifier ({token})")
            if not rel.startswith(IMPORTER) and MARKER not in line and not line.lstrip().startswith("//"):
                for pattern, why in IMPORTER_ONLY:
                    if re.search(pattern, line):
                        errors.append(f"{rel}:{n}: {why}")


def naming(errors: list[str]) -> None:
    for f in files():
        rel = str(f.relative_to(ROOT))
        if f.suffix not in {".swift", ".plist", ".strings", ".stringsdict", ".yml"}:
            continue
        text = f.read_text(errors="ignore")
        for key, value in PRODUCT_KEYS.findall(text):
            if ARC_WORD.search(value):
                errors.append(f"{rel}: {key} must not contain 'Arc' ({value.strip()})")
        if f.suffix != ".swift" or rel.startswith(IMPORTER):
            continue
        lines = text.splitlines()
        for n, line in enumerate(lines, 1):
            if line.lstrip().startswith("//"):
                continue  # comments aren't user-facing
            marked = MARKER in line or (n > 1 and MARKER in lines[n - 2])  # marker on the line or just above
            literals = " ".join(STRING_LITERAL.findall(line))
            if not literals:
                continue
            for pattern, why in NAMING:
                if re.search(pattern, literals):
                    errors.append(f"{rel}:{n}: {why}: {literals[:100]}")
            if ARC_WORD.search(literals) and not marked:
                errors.append(f"{rel}:{n}: user-facing 'Arc' needs `// {MARKER}` (nominative use only): {literals[:100]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rules", choices=["clean-room", "naming"])
    args = ap.parse_args()
    errors: list[str] = []
    if args.rules in (None, "clean-room"):
        clean_room(errors)
    if args.rules in (None, "naming"):
        naming(errors)
    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    label = args.rules or "clean-room + naming"
    print(f"✔ {label} OK ({len(files())} files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
