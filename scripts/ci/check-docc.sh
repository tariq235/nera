#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Documentation validation: build the DocC archives for every NeraKit module and fail on any DocC
# warning (broken symbol links, malformed doc comments). Complements check-public-docs.py
# (every public symbol documented) and check-doc-links.py (Markdown links/anchors).
set -euo pipefail
cd "$(dirname "$0")/../.."
LOG=build/docc.log
mkdir -p build
# Always recompile: warnings only appear when a file compiles, so an incremental build hides them. Only the build
# products go; resolved packages and module caches stay.
rm -rf build/DocC/Build
( cd Packages/NeraKit && xcodebuild docbuild -scheme NeraKit-Package -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ../../build/DocC > "../../$LOG" 2>&1 ) || { tail -30 "$LOG"; echo "✘ DocC build failed"; exit 1; }
WARN=$(grep -E "/Sources/.*: warning:" "$LOG" | sed 's#.*/Packages/#Packages/#; s# (in target.*##' | sort -u || true)
if [ -n "$WARN" ]; then
  echo "$WARN"
  echo "✘ $(echo "$WARN" | wc -l | tr -d ' ') documentation warning(s)"
  exit 1
fi
echo "✔ DocC: $(ls -d build/DocC/Build/Products/Debug/*.doccarchive | wc -l | tr -d ' ') module archives, no warnings"
