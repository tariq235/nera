#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Regenerates scripts/ci/data/arc-asset-hashes.txt from an installed Arc.app (hashes only, no content).
# Run after a new Arc release so the clean-room scanner knows its assets too (entries accumulate).
set -euo pipefail
cd "$(dirname "$0")/../.."
ARC_APP="${ARC_APP:-/Applications/Arc.app}"
OUT=scripts/ci/data/arc-asset-hashes.txt
V=$(plutil -extract CFBundleShortVersionString raw "$ARC_APP/Contents/Info.plist")
B=$(plutil -extract CFBundleVersion raw "$ARC_APP/Contents/Info.plist")
NEW=$(find "$ARC_APP" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.pdf' \
  -o -iname '*.svg' -o -iname '*.icns' -o -iname '*.car' -o -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff' -o -iname '*.woff2' \
  -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.caf' -o -iname '*.aif*' -o -iname '*.mp4' -o -iname '*.mov' \
  -o -iname '*.lottie' -o -iname '*.json' -o -iname '*.strings' -o -iname '*.stringsdict' -o -iname '*.nib' \) -print0 \
  | xargs -0 shasum -a 256 | awk '{print $1}')
{
  echo "# SHA-256 fingerprints of Arc resource files (latest added: $V build $B): images, icons, fonts, sounds, animations, UI text."
  echo "# Hashes only; no Arc content is stored. Used by check-clean-room.py to reject byte-identical copies."
  echo "# Regenerate: scripts/ci/generate-arc-asset-hashes.sh"
  { grep -v '^#' "$OUT" 2>/dev/null || true; echo "$NEW"; } | sed '/^$/d' | sort -u
} > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
echo "✔ $(grep -vc '^#' "$OUT") fingerprints in $OUT"
