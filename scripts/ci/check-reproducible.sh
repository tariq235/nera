#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Reproducibility (plan §7, nightly): build the macOS app twice from a clean state, unsigned, at the same path,
# and compare every Mach-O and resource. Differences are listed; the check fails if any remain.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/repro; DD=build/repro-dd
rm -rf "$OUT"; mkdir -p "$OUT"
for run in 1 2; do
  rm -rf "$DD"
  xcodebuild -project Nera.xcodeproj -scheme Nera -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" build -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" >/dev/null
  # embed-cef.sh signs ad hoc even when Xcode doesn't: strip signatures so only built content is compared.
  ditto "$DD/Build/Products/Release/Nera.app" "$OUT/$run/Nera.app"
  find "$OUT/$run/Nera.app" -name _CodeSignature -prune -exec rm -rf {} +
  find "$OUT/$run/Nera.app" -type f -perm +111 -exec sh -c 'codesign --remove-signature "$1" 2>/dev/null || true' _ {} \;
done
(cd "$OUT/1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$OUT/1.sums"
(cd "$OUT/2" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$OUT/2.sums"
if diff "$OUT/1.sums" "$OUT/2.sums" > "$OUT/diff.txt"; then
  echo "✔ reproducible: $(wc -l < "$OUT/1.sums" | tr -d ' ') files identical across two clean builds"
else
  echo "✘ $(grep -c '^<' "$OUT/diff.txt") file(s) differ between two clean builds:"; grep '^<' "$OUT/diff.txt" | awk '{print "   " $3}' | head -30
  exit 1
fi
