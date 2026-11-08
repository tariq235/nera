#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Installs the exact versions of the build and check tools CI uses, each checked against its SHA-256 (no unpinned
# installs). Tools go to build/tools/bin; add it to PATH:
#   ./scripts/ci/install-tools.sh && export PATH="$PWD/build/tools/bin:$PATH"
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$PWD/build/tools/bin"
WORK="$PWD/build/tools/download"
mkdir -p "$BIN" "$WORK"
[ "$(uname -m)" = arm64 ] || { echo "✘ Nera builds on Apple silicon Macs only (the pinned tools are arm64)"; exit 1; }

# name | version | URL | SHA-256 (Apple silicon)
TOOLS="
gitleaks|8.30.1|https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_darwin_arm64.tar.gz|b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5
osv-scanner|2.7.0|https://github.com/google/osv-scanner/releases/download/v2.7.0/osv-scanner_darwin_arm64|d4926ef8da134332543be276dff157e4c170f99ad91fc48e89448a8816bdf70b
swiftlint|0.65.1|https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip|c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
xcodegen|2.46.0|https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip|4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
ninja|1.13.2|https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-mac.zip|c99048673aa765960a99cf10c6ddb9f1fad506099ff0a0e137ad8960a88f321b
cmake|4.4.5|https://github.com/Kitware/CMake/releases/download/v4.4.5/cmake-4.4.5-macos-universal.tar.gz|679e77a96b9ef9484cc6c1445255fc4f84206b48a65420efbedf16bdab55fbff
"

echo "$TOOLS" | while IFS='|' read -r name version url sha; do
  [ -n "$name" ] || continue
  file="$WORK/$name-$version-$(basename "$url")"   # versioned: a bump never reuses an old download
  [ -f "$file" ] || curl -fsSL -o "$file" "$url"
  echo "$sha  $file" | shasum -a 256 -c --quiet || { echo "✘ $name $version: checksum mismatch"; rm -f "$file"; exit 1; }
  dir="$WORK/$name"
  rm -rf "$dir" && mkdir -p "$dir"
  case "$file" in
    *.tar.gz) tar -xzf "$file" -C "$dir" ;;
    *.zip) unzip -q "$file" -d "$dir" ;;
    *) cp "$file" "$dir/$name" && chmod +x "$dir/$name" ;;
  esac
  case "$name" in
    cmake) ln -sf "$(find "$dir" -path '*CMake.app/Contents/bin/cmake' | head -1)" "$BIN/cmake" ;;
    xcodegen) ln -sf "$(find "$dir" -name xcodegen -type f -perm -u+x | head -1)" "$BIN/xcodegen" ;;
    *) ln -sf "$(find "$dir" -name "$name" -type f | head -1)" "$BIN/$name" ;;
  esac
  echo "✔ $name $version"
done
