#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
set -euo pipefail
xcrun simctl list devices available -j | python3 -I -c '
import json, sys, re
d = json.load(sys.stdin)["devices"]
def ver(k):
    m = re.search(r"iOS-(\d+)-(\d+)", k); return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for runtime in sorted((k for k in d if "iOS" in k), key=ver, reverse=True):
    phones = [x for x in d[runtime] if x["name"].startswith("iPhone")]
    if phones: print(phones[0]["udid"]); break
else: sys.exit("no iPhone simulator installed")
'
