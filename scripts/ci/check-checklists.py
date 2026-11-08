#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Validate /checklists so that a checked box always means "proven".

Item format (one line):
  - [x] **SEC-014** Title — P0 · owner: nera · evidence: test:SecurityPolicyTests/httpIsUpgradedInHTTPSOnlyMode, doc:docs/x.md

Rules enforced:
  * every "- [" line must match the format; IDs are unique across all checklists
  * a checked item needs real evidence (test:/ci:/doc:/file:) and no "planned:"
  * every cited test function / path must exist
  * in 000 (Browser Security) a checked P0 item must cite a test: or ci: (a doc alone is not proof)
  * template checklists (<!-- checklist: template -->) are format-checked only

Usage:
  check-checklists.py                 validate + print status
  check-checklists.py --gate foundation   also fail if any P0 item in the release gate lists is open
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKLISTS = ROOT / "checklists"
FOUNDATION_GATE = {"000", "002", "005", "007", "010", "011"}

ITEM = re.compile(
    r"^- \[(?P<done>[ x])\] \*\*(?P<id>[A-Z0-9]+-\d{3})\*\* (?P<title>.+?) — "
    r"(?P<prio>P[0-2]) · owner: (?P<owner>nera|engine|os|maintainer) · evidence: (?P<evidence>.+)$"
)
EVIDENCE_KINDS = {"test", "ci", "doc", "file", "planned"}


def find_test(target: str, name: str) -> bool:
    roots = list(ROOT.glob(f"Packages/*/Tests/{target}")) + list(ROOT.glob(f"Packages/*/Sources/{target}"))
    if target.endswith("UITests"):
        roots.append(ROOT / "UITests")
    pattern = re.compile(rf"\bfunc\s+{re.escape(name)}\s*\(")
    return any(pattern.search(p.read_text(errors="ignore")) for r in roots for p in r.rglob("*.swift"))


def check_evidence(token: str) -> str | None:
    kind, _, value = token.partition(":")
    kind, value = kind.strip(), value.strip()
    if kind not in EVIDENCE_KINDS or not value:
        return f"unknown evidence '{token}' (use {', '.join(sorted(EVIDENCE_KINDS))})"
    if kind == "test":
        target, _, name = value.partition("/")
        if not name or not find_test(target, name):
            return f"test not found: {value}"
    elif kind in {"ci", "doc", "file"}:
        if not (ROOT / value.split("#")[0]).exists():
            return f"path not found: {value}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", choices=["foundation"])
    args = ap.parse_args()

    errors: list[str] = []
    seen: dict[str, str] = {}
    rows = []
    open_gate_items: list[str] = []

    files = sorted(CHECKLISTS.glob("[0-9][0-9][0-9]-*.md"))
    if not files:
        print("no checklists found", file=sys.stderr)
        return 1

    for path in files:
        number = path.name[:3]
        text = path.read_text()
        template = "<!-- checklist: template -->" in text
        total = done = p0 = p0_done = 0
        for lineno, line in enumerate(text.splitlines(), 1):
            if not line.startswith("- ["):
                continue
            where = f"{path.relative_to(ROOT)}:{lineno}"
            m = ITEM.match(line)
            if not m:
                errors.append(f"{where}: malformed item (see checklists/README.md)")
                continue
            item_id, checked = m["id"], m["done"] == "x"
            if item_id in seen:
                errors.append(f"{where}: duplicate ID {item_id} (also in {seen[item_id]})")
            seen[item_id] = where
            tokens = [t.strip() for t in m["evidence"].split(",") if t.strip() and t.strip() != "—"]
            for t in tokens:
                if err := check_evidence(t):
                    errors.append(f"{where}: {item_id}: {err}")
            if template:
                continue
            kinds = {t.partition(":")[0].strip() for t in tokens}
            if checked:
                if not kinds & {"test", "ci", "doc", "file"}:
                    errors.append(f"{where}: {item_id} is checked but cites no evidence")
                if "planned" in kinds:
                    errors.append(f"{where}: {item_id} is checked but still says planned:")
                if number == "000" and m["prio"] == "P0" and not kinds & {"test", "ci"}:
                    errors.append(f"{where}: {item_id} is a checked P0 security item; it needs test: or ci: evidence")
            total += 1
            done += checked
            if m["prio"] == "P0":
                p0 += 1
                p0_done += checked
                if not checked and number in FOUNDATION_GATE:
                    open_gate_items.append(f"{item_id} ({path.name})")
        rows.append((path.name, "template" if template else f"{done}/{total}", "—" if template else f"{p0_done}/{p0}"))

    width = max(len(r[0]) for r in rows)
    print(f"{'checklist'.ljust(width)}  done     P0 done")
    for name, d, p in rows:
        print(f"{name.ljust(width)}  {d.ljust(8)} {p}")
    print(f"\nrelease gate: {len(open_gate_items)} open P0 item(s)")

    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    if args.gate == "foundation" and open_gate_items:
        print("✘ release gate not met: " + ", ".join(open_gate_items), file=sys.stderr)
        return 1
    print("✔ checklists valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
