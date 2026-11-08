#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Developer machine setup. Idempotent.
set -euo pipefail
xcodebuild -version >/dev/null 2>&1 || { echo "Install Xcode 26+ from the App Store"; exit 1; }

# The exact tool versions CI uses, each checked by SHA-256 (build/tools/bin; the Makefile puts it first on PATH).
./scripts/ci/install-tools.sh
export PATH="$PWD/build/tools/bin:$PATH"

./scripts/engine/prepare-cef.sh && xcodegen generate --quiet
echo "Ready. Try: make test"
