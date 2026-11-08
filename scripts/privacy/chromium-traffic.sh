#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Privacy audit of Chromium's own network traffic (PRV-006): runs a Debug Nera on a clean, throwaway profile,
# first idle on the start page, then with one page open, and lists every host Chromium contacted. Anything other
# than the opened page (and loopback) is a background request and fails the audit.
#
#   scripts/privacy/chromium-traffic.sh [<Nera.app>] [idle seconds]
set -uo pipefail
cd "$(dirname "$0")/../.."
APP="$(cd "$(dirname "${1:-build/dd/Build/Products/Debug/Nera.app}")" && pwd)/$(basename "${1:-Nera.app}")"
IDLE="${2:-90}"
OUT="$(mktemp -d)"
[ -x "$APP/Contents/MacOS/Nera" ] || { echo "✘ $APP not built (Debug)"; exit 1; }

run() {  # $1 label, $2 netlog, $3 page to open (optional)
  local label="$1" log="$2" page="${3:-}"
  echo "→ $label (${IDLE}s)"
  NERA_UI_TEST=1 NERA_NETLOG="$log" "$APP/Contents/MacOS/Nera" >/dev/null 2>&1 &
  local pid=$!
  sleep 5
  [ -n "$page" ] && open -a "$APP" "$page"  # as a link from another app
  sleep "$IDLE"
  kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null
}

run "idle on the start page" "$OUT/idle.json"
# KNOWN_HOSTS: hosts already disclosed in docs/security/security-model.md (the nightly job passes them).
python3 -I scripts/privacy/chromium-traffic.py "$OUT/idle.json" --allow ${KNOWN_HOSTS:-}; idle=$?
run "one page open (example.com)" "$OUT/page.json" https://example.com/
python3 -I scripts/privacy/chromium-traffic.py "$OUT/page.json" --allow example.com ${KNOWN_HOSTS:-}; page=$?
echo "net logs: $OUT"
[ $idle -eq 0 ] && [ $page -eq 0 ]
