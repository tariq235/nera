#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Xcode build phase (last phase of the macOS Nera target): embeds the Chromium Embedded Framework and
# signs every nested bundle inside out with the hardened runtime and per-bundle entitlements
# (ADR-0006/0009: only the Renderer helper gets allow-jit). Xcode then signs Nera.app itself.
set -euo pipefail
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
FW="$APP/Contents/Frameworks"
CEF_FW="Chromium Embedded Framework.framework"
mkdir -p "$FW"
# CEF ships a flat framework (binary, Libraries/, Resources/ at the top). Install it in the standard
# versioned macOS layout, which Xcode's product validation requires; the top-level names become
# symlinks, so CEF's loader and Chromium's resource lookup see the same paths.
DEST="$FW/$CEF_FW"
rm -rf "$DEST"
mkdir -p "$DEST/Versions/A"
ditto "$CEF_ROOT/Release/$CEF_FW" "$DEST/Versions/A"
ln -s A "$DEST/Versions/Current"
for item in "Chromium Embedded Framework" Libraries Resources; do ln -s "Versions/Current/$item" "$DEST/$item"; done

ID="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$ID" ] || ID="-"   # ad hoc (local builds without a signing identity)
# Hardened runtime everywhere, except ad-hoc Debug builds: Xcode signs those without it, and with it
# library validation would refuse the ad-hoc CEF framework (no Team ID). Release builds always get it.
HARDENED=1
if [ "$ID" = "-" ] && [ "${CONFIGURATION:-}" = "Debug" ]; then HARDENED=0; fi
sign() {
  # Notarization needs a secure timestamp on every binary; ad-hoc builds don't get one.
  local ts="--timestamp=none"; [ "$ID" = "-" ] || ts="--timestamp"
  if [ $HARDENED = 1 ]; then codesign --force --options runtime "$ts" --sign "$ID" "$@"
  else codesign --force "$ts" --sign "$ID" "$@"; fi
}
for lib in "$FW/$CEF_FW/Libraries/"*.dylib; do sign "$lib"; done
sign "$FW/$CEF_FW"
for helper in "$FW"/*Helper*.app; do
  case "$helper" in
    *"(Renderer).app") sign --entitlements "$SRCROOT/Apps/macOS/ChromiumHelper/Renderer.entitlements" "$helper" ;;
    *) sign "$helper" ;;
  esac
done
# Third-party notices for everything Chromium bundles (license requirement; THIRD_PARTY_NOTICES.md).
mkdir -p "$APP/Contents/Resources"
cp "$CEF_ROOT/CREDITS.html" "$APP/Contents/Resources/Chromium Credits.html"
cp "$(dirname "$0")/../../THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
echo "✔ embedded and signed CEF + helpers (identity: $ID)"
