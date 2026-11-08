#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Runs the macOS app's Debug-only engine self-test (real Chromium + WebKit conformance, Chromium security
# configuration) and fails on any failure or after 3 minutes. Writes build/conformance/*.json for
# scripts/ci/render-engine-matrix.py. Usage: engine-self-test.sh [path/to/Nera.app]
set -uo pipefail
cd "$(dirname "$0")/../.."
APP="${1:-build/DerivedData/Build/Products/Debug/Nera.app}"
[ -x "$APP/Contents/MacOS/Nera" ] || { echo "✘ $APP not built (Debug)"; exit 1; }
LOG="$(mktemp)"
# The conformance extension fixture (X-cases): a content blocker + content script, loaded in Debug only.
export NERA_DEBUG_EXTENSIONS="$PWD/Tests/Fixtures/extensions/nera-test-blocker"
(cd "$(mktemp -d)" && "$OLDPWD/$APP/Contents/MacOS/Nera" --engine-self-test >"$LOG" 2>&1) &
pid=$!
for _ in $(seq 1 180); do kill -0 $pid 2>/dev/null || break; sleep 1; done
if kill -0 $pid 2>/dev/null; then kill $pid; echo "✘ engine self-test timed out"; grep engine-self-test "$LOG"; exit 1; fi
wait $pid; status=$?
grep engine-self-test "$LOG"
exit $status
