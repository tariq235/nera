#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Dependency vulnerability scan (SEC-065): OSV-Scanner over every SwiftPM lockfile in git.
# Nera has no third-party packages today, so this passes with a note; it starts biting the moment
# one is added. GitHub Actions versions are covered by Dependabot; the CEF/Chromium version check
# runs nightly (check-cef-version.py).
set -euo pipefail
export PATH="$(cd "$(dirname "$0")/../.." && pwd)/build/tools/bin:$PATH"   # pinned tools (make bootstrap)
cd "$(dirname "$0")/../.."
command -v osv-scanner >/dev/null || { echo "✘ osv-scanner not installed (brew install osv-scanner)"; exit 1; }
LOCKS=$(git ls-files '*Package.resolved')   # macOS bash 3.2: no mapfile
if [ -z "$LOCKS" ]; then
  echo "✔ no third-party dependency lockfiles (Nera ships no third-party packages)"
  exit 0
fi
ARGS=""
for f in $LOCKS; do ARGS="$ARGS --lockfile $f"; done
# shellcheck disable=SC2086
osv-scanner scan source $ARGS
echo "✔ no known vulnerabilities in $(echo "$LOCKS" | wc -l | tr -d ' ') lockfile(s)"
