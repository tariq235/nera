#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Static analysis of Nera's own C, Objective-C and C++ code (SEC-068): the Chromium bridge and helper. Swift is
# covered by CodeQL. Fails on any analyzer finding in Nera's files (CEF's headers are third-party and excluded).
set -uo pipefail
cd "$(dirname "$0")/../.."
LOG=build/analyze.log
mkdir -p build
xcodebuild clean analyze -project Nera.xcodeproj -scheme Nera -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/analyze-dd >"$LOG" 2>&1 || { tail -20 "$LOG"; echo "✘ analyze build failed"; exit 1; }
# Any warning in Nera's own sources fails, with or without the analyzer's [checker] suffix.
findings=$(grep -E "/Apps/macOS/[^:]+:[0-9]+:[0-9]+: warning:" "$LOG" | sort -u)
if [ -n "$findings" ]; then echo "$findings"; echo "✘ static analyzer findings in Nera's code"; exit 1; fi
count=$(grep -cE "^Analyze(Shallow)? " "$LOG" || true)
[ "$count" -gt 0 ] || { echo "✘ the analyzer analyzed nothing (check the scheme)"; exit 1; }
echo "✔ static analysis clean ($count files analyzed)"
