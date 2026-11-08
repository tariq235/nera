#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Is Nera's pinned Chromium the latest stable CEF build? (SEC-072, SIGN-004)

Compares the version pinned in scripts/engine/fetch-cef.sh with the newest stable macOS arm64 build in the CEF build
index. Exits 1 when a newer stable build exists, so the nightly job fails loudly and a Chromium update starts
(checklists/006-chromium-upgrade.md; SLA: 7 days, 48 hours when exploited).
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX = "https://cef-builds.spotifycdn.com/index.json"


def version_key(v: str) -> tuple:
    """Chromium version first, then CEF's own (a CEF-only security fix keeps the Chromium version)."""
    cef, _, chromium = v.partition("+chromium-")
    cef_numbers = tuple(int(x) for x in re.findall(r"\d+", cef.split("+")[0]))
    return tuple(int(x) for x in re.findall(r"\d+", chromium)) + cef_numbers


def main() -> int:
    pinned = re.search(r'CEF_VERSION="([^"]+)"', (ROOT / "scripts/engine/fetch-cef.sh").read_text()).group(1)
    try:
        with urllib.request.urlopen(INDEX, timeout=60) as response:
            index = json.load(response)
        stable = [v["cef_version"] for v in index["macosarm64"]["versions"] if v.get("channel") == "stable"]
    except Exception as error:  # network or format problems: not the same as "an update is needed"
        print(f"⚠ couldn't check the CEF build index ({type(error).__name__}); try again later")
        return 2
    latest = max(stable, key=version_key)
    if version_key(latest) > version_key(pinned):
        print(f"✘ newer stable Chromium available: {latest} (pinned {pinned}). Start the Chromium update (SLA 7 days).")
        return 1
    print(f"✔ pinned Chromium is the latest stable: {pinned}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
