#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Release-only checks on the built app (REL-016, SR-020):
#   - third-party notices are bundled (ours and Chromium's)
#   - no Debug-only test hooks made it into the binary
#   - no bundle carries get-task-allow (debugger attach; notarization rejects it)
set -euo pipefail
APP="${1:?usage: check-release-bundle.sh Nera.app}"
fail=0
for f in "THIRD_PARTY_NOTICES.md" "Chromium Credits.html"; do
  [ -s "$APP/Contents/Resources/$f" ] || { echo "✘ missing $f in Contents/Resources"; fail=1; }
done
STRINGS=$(find "$APP/Contents/MacOS" -type f -exec strings -a {} + 2>/dev/null)
# Strings only Debug test code contains. (Switch names such as host-resolver-rules legitimately appear in Release:
# the forbidden-switch list names them.)
for marker in "--engine-self-test" "NeraTestChromium" "MAP mixed.nera.test" "engine-self-test:"; do
  if grep -qF -- "$marker" <<<"$STRINGS"; then echo "✘ Debug-only test hook in the Release binary: $marker"; fail=1; fi
done
while IFS= read -r -d '' bundle; do
  if codesign -d --entitlements - "$bundle" 2>/dev/null | grep -q "get-task-allow"; then
    echo "✘ get-task-allow in $(basename "$bundle")"; fail=1
  fi
done < <(find "$APP" -name "*.app" -print0)
[ $fail -eq 0 ] && echo "✔ release bundle OK (notices bundled, no test hooks, no get-task-allow)"
exit $fail
