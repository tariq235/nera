#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Every hard-coded https:// host in shipped source must be listed in docs/security/security-model.md
# ("Network inventory"). This keeps "no surprise network calls" true as the code grows.
set -euo pipefail
cd "$(dirname "$0")/../.."

INVENTORY="docs/security/security-model.md"
# SiteCheck.swift and DemoMode.swift are Debug-only tools that *visit* sites like a user would; not requests of Nera's own.
# The MPL-2.0 license header names the license's URL; it's a comment, never contacted.
hosts=$(grep -rhE --include='*.swift' --exclude='SiteCheck.swift' --exclude='DemoMode.swift' 'https?://' Packages/NeraKit/Sources Apps \
  | grep -v 'https://mozilla.org/MPL/2.0/' | grep -oE 'https?://[a-zA-Z0-9.-]+\.[a-z]{2,}' \
  | sed -E 's#https?://##' | sort -u \
  | grep -vE '(^|\.)example\.(com|org|net)$|\.test$' || true)  # RFC 2606 names never resolve publicly

fail=0
for h in $hosts; do
  grep -q "\`$h\`" "$INVENTORY" || { echo "✘ host '$h' is used in source but not listed in $INVENTORY"; fail=1; }
done
# The runtime allowlist (SEC-063) must match the inventory too.
allow=$(python3 -I -c 'import re,sys; s=open(sys.argv[1]).read(); m=re.search(r"static let nera = NetworkAllowlist\(hosts: \[(.*?)\]\)", s, re.S); print("\n".join(re.findall(r"\"([^\"]+)\"", m.group(1))) if m else "MISSING")' Packages/NeraKit/Sources/Networking/NeraHTTPClient.swift)
[ "$allow" = "MISSING" ] && { echo "✘ NetworkAllowlist.nera not found"; fail=1; }
for h in $allow; do
  [ "$h" = "MISSING" ] && continue
  grep -q "\`${h#.}\`" "$INVENTORY" || { echo "✘ allowlisted host '$h' is not listed in $INVENTORY"; fail=1; }
done
[ $fail -eq 0 ] && echo "✔ network inventory OK ($(echo "$hosts" | grep -c . || true) hosts in source, $(echo "$allow" | grep -c . || true) allowlisted)"
exit $fail
