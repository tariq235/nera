#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Builds a release Nera.dmg on this Mac (the same steps as .github/workflows/release.yml, for the maintainer).
#
#   scripts/release/make-dmg.sh
#
# Signing: uses the first "Developer ID Application" identity in the keychain; without one it builds an ad-hoc
# signed DMG (people then open it with right-click ▸ Open, like other unsigned open-source apps).
# Notarization: runs when a notarytool keychain profile named "nera-notary" exists. Create it once with:
#   xcrun notarytool store-credentials nera-notary --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
# Release notes and build number: a notes file given as NERA_NOTES_FILE (its newest "## Build N" entry), otherwise
# BUILD=<n> from the environment and the newest section of CHANGELOG.md. The build number is stamped into the app
# (CFBundleVersion); updates compare it.
NOTES_FILE="${NERA_NOTES_FILE:-}"
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  BUILD=$(grep -m1 -E '^## Build [0-9]+' "$NOTES_FILE" | sed -E 's/^## Build ([0-9]+).*/\1/')
  NOTES_PATTERN='^## Build [0-9]+'
else
  NOTES_FILE=CHANGELOG.md
  BUILD="${BUILD:-}"
  NOTES_PATTERN='^## '
fi
[ -n "$BUILD" ] || { echo "✘ no build number: add a '## Build N' entry to $NOTES_FILE, or set BUILD=<n>"; exit 1; }
OUT=build/release-dmg
DD=build/release-dd
rm -rf "$OUT"; mkdir -p "$OUT"

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
SIGNING=()
if [ -n "$IDENTITY" ]; then
  TEAM=$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<< "$IDENTITY")
  echo "→ signing with: $IDENTITY"
  SIGNING=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM")
else
  echo "→ no Developer ID certificate: ad-hoc build"
  IDENTITY="-"
fi

make project >/dev/null
# Safe Browsing key from the Keychain; without it the build ships with the protection unavailable.
SB_KEY=$(security find-generic-password -s "Nera Safe Browsing Key" -a nera -w 2>/dev/null || true)
[ -n "$SB_KEY" ] || echo "⚠ no Safe Browsing key in the Keychain: this build can't warn about dangerous sites"
xcodebuild -project Nera.xcodeproj -scheme Nera -configuration Release -destination 'platform=macOS' -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO CURRENT_PROJECT_VERSION="$BUILD" \
  NERA_SAFE_BROWSING_KEY="$SB_KEY" \
  ${SIGNING[@]+"${SIGNING[@]}"} build -quiet
APP="$DD/Build/Products/Release/Nera.app"

# The app must carry this version and build: updates compare build numbers (ADR-0011).
GOT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
GOT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
[ "$GOT_VERSION" = "$VERSION" ] && [ "$GOT_BUILD" = "$BUILD" ] || {
  echo "✘ app says $GOT_VERSION ($GOT_BUILD), expected $VERSION ($BUILD)"; exit 1; }

./scripts/ci/check-entitlements.sh "$APP"
./scripts/release/check-release-bundle.sh "$APP"

if [ "$IDENTITY" != "-" ] && xcrun notarytool history --keychain-profile nera-notary >/dev/null 2>&1; then
  echo "→ notarizing the app"
  ditto -c -k --keepParent "$APP" "$OUT/Nera.zip"
  xcrun notarytool submit "$OUT/Nera.zip" --keychain-profile nera-notary --wait
  xcrun stapler staple "$APP"
  rm "$OUT/Nera.zip"
  NOTARIZE=1
fi

# Drag-to-Applications disk image: Nera's own background, Nera on the left, Applications on the right.
# dmgbuild (build-time only, in a local venv) writes the window layout without scripting Finder.
DMG="$OUT/Nera.dmg"
VENV=build/venv-dmg
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r scripts/release/requirements-dmg.txt; }
ART="$OUT/art"; mkdir -p "$ART"
swift scripts/release/dmg-background.swift "$ART" >/dev/null
tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" >/dev/null 2>&1
# This build's notes, as a plain text file in the disk image.
# MPL-2.0 §3.2: whoever gets this DMG must be able to get the source. Until the public repository exists, only the
# maintainer's own builds may skip this (ALLOW_UNPUBLISHED_SOURCE=1); never for anyone else.
SOURCE_URL=$(/usr/libexec/PlistBuddy -c "Print NeraSourceURL" "$APP/Contents/Info.plist")
if ! curl -fsSLI -o /dev/null "$SOURCE_URL"; then
  [ "${ALLOW_UNPUBLISHED_SOURCE:-0}" = 1 ] || { echo "✘ the source link $SOURCE_URL isn't public: don't hand this DMG to anyone (ALLOW_UNPUBLISHED_SOURCE=1 for your own builds)"; exit 1; }
  echo "⚠ source link not public yet: this DMG is for the maintainer only"
fi
NOTES="$ART/Release Notes.txt"
{
  echo "Nera $VERSION (build $BUILD): release notes"
  echo
  awk -v pattern="$NOTES_PATTERN" '$0 ~ pattern { n++ } n == 1' "$NOTES_FILE"
  echo
  # MPL-2.0 §3.2: tell recipients where the source is (SourceAvailability.swift says the same).
  echo "Source code: Nera is open source under the Mozilla Public License 2.0:"
  echo "$SOURCE_URL"
} > "$NOTES"
"$VENV/bin/dmgbuild" -s scripts/release/dmg-settings.py -D app="$APP" -D background="$ART/background.tiff" -D notes="$NOTES" \
  "Nera $VERSION" "$DMG" >/dev/null
rm -rf "$ART"
if [ "$IDENTITY" != "-" ]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  if [ "${NOTARIZE:-0}" = 1 ]; then
    echo "→ notarizing the disk image"
    xcrun notarytool submit "$DMG" --keychain-profile nera-notary --wait
    xcrun stapler staple "$DMG"
  fi
fi
# Update feed (ADR-0011): sign the final disk image with the update key (maintainer's Keychain item "Nera Update
# Signing Key") and add it to appcast.xml. Upload both to the GitHub release tagged $TAG on the public repo.
# FEED=<previous appcast.xml> keeps earlier releases in the feed.
TAG="${TAG:-v$VERSION-build$BUILD}"
ASSET="Nera-$VERSION-$BUILD.dmg"
cp "$DMG" "$OUT/$ASSET"
if KEY=$(security find-generic-password -s "Nera Update Signing Key" -a nera -w 2>/dev/null); then
  read -r SIG LEN < <(SPARKLE_ED_PRIVATE_KEY="$KEY" swift scripts/release/sign-update.swift sign "$OUT/$ASSET")
  unset KEY
  [ -n "${FEED:-}" ] && cp "$FEED" "$OUT/appcast.xml"
  python3 -I scripts/release/make-appcast.py --feed "$OUT/appcast.xml" --build "$BUILD" --version "$VERSION" \
    --url "https://github.com/tariq235/nera/releases/download/$TAG/$ASSET" --signature "$SIG" --length "$LEN" --min-os 14.0
  echo "→ update feed: $OUT/appcast.xml (upload it and $ASSET to release $TAG)"
else
  echo "→ no update signing key in the Keychain: no appcast.xml (development DMG)"
fi
shasum -a 256 "$DMG" | tee "$OUT/SHA256SUMS"
echo "✔ $DMG ($(du -h "$DMG" | cut -f1)), version $VERSION build $BUILD, signed: $([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY"), notarized: $([ "${NOTARIZE:-0}" = 1 ] && echo yes || echo no)"
