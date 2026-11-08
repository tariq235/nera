#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Downloads the pinned CEF binary distribution into a cache outside the repo (never committed),
# verifies it (SHA-1 published by the CEF build server + Nera's pinned SHA-256), and prints its path.
# Pin bump procedure: checklists/006-chromium-upgrade.md.
set -euo pipefail

CEF_VERSION="156.0.15+gcf671c0+chromium-156.0.8078.80"
CEF_PLATFORM="macosarm64"
CEF_SHA1="77fc8778dfd008c6c85c1668b38462597804dc89"    # from cef-builds.spotifycdn.com/index.json
CEF_SHA256="938081b5bb552b4990b9667662d9909429d2c113d862c83826322310835666f9"

NAME="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}"
CACHE="${NERA_CEF_CACHE:-$HOME/Library/Caches/Nera/cef}"
ARCHIVE="$CACHE/$NAME.tar.bz2"
URL="https://cef-builds.spotifycdn.com/${NAME//+/%2B}.tar.bz2"
mkdir -p "$CACHE"

# NERA_CEF_VERIFY=1 (releases): never trust an extracted copy; re-check the archive and extract it fresh.
if [ "${NERA_CEF_VERIFY:-0}" = 1 ]; then rm -rf "${CACHE:?}/$NAME"; fi
if [ ! -d "$CACHE/$NAME" ]; then
  [ -f "$ARCHIVE" ] || curl -fL --retry 3 -o "$ARCHIVE.part" "$URL" && { [ -f "$ARCHIVE" ] || mv "$ARCHIVE.part" "$ARCHIVE"; }
  GOT1=$(shasum -a 1 "$ARCHIVE" | cut -d' ' -f1)
  GOT256=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
  [ "$GOT1" = "$CEF_SHA1" ] || { echo "✘ SHA-1 mismatch: $GOT1" >&2; rm -f "$ARCHIVE"; exit 1; }
  if [ "$CEF_SHA256" != "PENDING" ] && [ "$GOT256" != "$CEF_SHA256" ]; then
    echo "✘ SHA-256 mismatch: $GOT256" >&2; rm -f "$ARCHIVE"; exit 1
  fi
  tar -xjf "$ARCHIVE" -C "$CACHE"
  echo "✔ CEF $CEF_VERSION verified (sha256 $GOT256)" >&2
fi
echo "$CACHE/$NAME"
