#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Binary size gate (PERF-010; docs/standards/performance-budget.md).

  check-binary-size.py <platform> <path/to/App.app> [--baseline build/size-baseline] [--out build/size]

- Fails if the app exceeds its absolute budget (scripts/ci/data/size-budget.json).
- Fails if it grew more than `max_growth_percent` versus the baseline report from `main`'s last
  successful CI run (when one is available), unless SIZE_GROWTH_APPROVED=1 (PR label
  'size-increase-approved').
- Writes <out>/<platform>.json for the next comparison.
Size = sum of file sizes in the bundle (not disk blocks), so it's identical on every machine.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUDGET = ROOT / "scripts" / "ci" / "data" / "size-budget.json"


def bundle_bytes(app: Path) -> int:
    return sum(f.stat().st_size for f in app.rglob("*") if f.is_file() and not f.is_symlink())


def mb(n: int) -> str:
    return f"{n / 1_000_000:.2f} MB"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("platform", choices=["macos", "ios"])
    ap.add_argument("app", type=Path)
    ap.add_argument("--baseline", type=Path, default=ROOT / "build" / "size-baseline")
    ap.add_argument("--out", type=Path, default=ROOT / "build" / "size")
    args = ap.parse_args()

    if not args.app.is_dir():
        print(f"✘ {args.app} not found (build it first)", file=sys.stderr)
        return 1
    budget = json.loads(BUDGET.read_text())
    limit = budget[args.platform]["max_bytes"]
    growth_limit = budget["max_growth_percent"]
    size = bundle_bytes(args.app)

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / f"{args.platform}.json").write_text(json.dumps({"platform": args.platform, "bytes": size}, indent=2) + "\n")

    errors = []
    if size > limit:
        errors.append(f"{args.platform} app is {mb(size)}, over its {mb(limit)} budget")
    baseline_file = args.baseline / f"{args.platform}.json"
    note = "no baseline from main yet"
    if baseline_file.exists():
        base = json.loads(baseline_file.read_text())["bytes"]
        growth = (size - base) / base * 100 if base else 0
        note = f"{growth:+.2f}% vs main ({mb(base)})"
        if growth > growth_limit:
            if os.environ.get("SIZE_GROWTH_APPROVED") == "1":  # PR label 'size-increase-approved' (CI sets this)
                note += " — growth above the limit approved by PR label"
            else:
                errors.append(f"{args.platform} app grew {growth:.2f}% (limit {growth_limit}%): {mb(base)} → {mb(size)}"
                              " (a reviewer can approve with the PR label 'size-increase-approved')")

    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"✔ {args.platform} app {mb(size)} (budget {mb(limit)}; {note})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
