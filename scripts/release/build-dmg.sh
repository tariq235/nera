#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Builds Nera's drag-to-Applications disk image: Nera on the left, Applications on the right, over Nera's own
# background, with the release notes and the source link (MPL-2.0 §3.2) as a text file. Used by make-dmg.sh and the
# release workflow, so both ship the same disk image. It doesn't sign it.
#
#   ./scripts/release/build-dmg.sh <Nera.app> <version> <notes.txt> <out.dmg>
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -eq 4 ] || { sed -n '7p' "$0" | sed 's/^# *//'; exit 2; }
APP="$1"; VERSION="$2"; NOTES_IN="$3"; DMG="$4"
# dmgbuild (build-time only, in a local venv) writes the window layout without scripting Finder.
VENV=build/venv-dmg
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r scripts/release/requirements-dmg.txt; }
ART=$(mktemp -d); trap 'rm -rf "$ART"' EXIT
swift scripts/release/dmg-background.swift "$ART" >/dev/null
tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" >/dev/null 2>&1
SOURCE_URL=$(/usr/libexec/PlistBuddy -c "Print NeraSourceURL" "$APP/Contents/Info.plist")
NOTES="$ART/Release Notes.txt"
{
  echo "Nera $VERSION: release notes"
  echo
  cat "$NOTES_IN"
  echo
  # MPL-2.0 §3.2: tell recipients where the source is (SourceAvailability.swift says the same).
  echo "Source code: Nera is open source under the Mozilla Public License 2.0:"
  echo "$SOURCE_URL"
} > "$NOTES"
mkdir -p "$(dirname "$DMG")"
"$VENV/bin/dmgbuild" -s scripts/release/dmg-settings.py -D app="$APP" -D background="$ART/background.tiff" -D notes="$NOTES" \
  "Nera $VERSION" "$DMG" >/dev/null
echo "✔ disk image: $DMG ($(( $(stat -f %z "$DMG") / 1000000 )) MB)"
