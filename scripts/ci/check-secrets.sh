#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Secret scanning (SEC-064): every commit reachable from HEAD, i.e. exactly what's in git.
# Untracked/ignored local files (build output, research evidence) are deliberately out of scope.
set -euo pipefail
export PATH="$(cd "$(dirname "$0")/../.." && pwd)/build/tools/bin:$PATH"   # pinned tools (make bootstrap)
cd "$(dirname "$0")/../.."
command -v gitleaks >/dev/null || { echo "✘ gitleaks not installed (brew install gitleaks)"; exit 1; }
gitleaks git --redact --no-banner --log-level warn --exit-code 1 .
echo "✔ no secrets in git history ($(git rev-list --count HEAD) commits)"
