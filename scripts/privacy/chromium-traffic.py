#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Lists every host Nera's Chromium contacted, from a Chromium net log (PRV-006).

  python3 -I scripts/privacy/chromium-traffic.py <netlog.json> [--allow host ...]

Reads the URL of every request and socket in the log, prints the hosts with counts, and exits 1 if any host isn't in
the allowed list (the pages the audit opened, plus loopback).
"""
import json
import sys
from collections import Counter
from urllib.parse import urlparse


def hosts(path: str) -> Counter:
    with open(path) as f:
        text = f.read()
    # A log cut short by a quit lacks its closing brackets; close them so it parses.
    try:
        log = json.loads(text)
    except json.JSONDecodeError:
        log = json.loads(text.rstrip().rstrip(",") + "]}")
    found: Counter = Counter()
    for event in log.get("events", []):
        params = event.get("params") or {}
        for key in ("url", "original_url", "host", "host_and_port"):
            value = params.get(key)
            if not isinstance(value, str) or not value:
                continue
            host = urlparse(value).hostname if "://" in value else value.split(":")[0]
            if host:
                found[host.lower()] += 1
    return found


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    allowed = set(args[args.index("--allow") + 1 :]) if "--allow" in args else set()
    allowed |= {"127.0.0.1", "localhost", "::1"}
    found = hosts(args[0])
    unexpected = [h for h in found if h not in allowed and not any(h.endswith("." + a) for a in allowed)]
    for host, count in found.most_common():
        mark = "✘" if host in unexpected else "✔"
        print(f"{mark} {host} ({count})")
    if unexpected:
        print(f"✘ {len(unexpected)} host(s) contacted that the audit didn't open")
        return 1
    print(f"✔ only the opened sites were contacted ({len(found)} host(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
