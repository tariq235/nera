#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Builds CEF's C++ wrapper library (libcef_dll_wrapper.a) for the pinned CEF, cached outside the repo.
set -euo pipefail
CEF_ROOT="${1:?usage: build-cef-wrapper.sh <cef root from fetch-cef.sh>}"
VERSION=$(basename "$CEF_ROOT" | sed -E 's/^cef_binary_([0-9.]+)\+.*/\1/')
OUT="${NERA_CEF_BUILD:-$HOME/Library/Caches/Nera/cef-build-$VERSION}"
if [ ! -f "$OUT/libcef_dll_wrapper/libcef_dll_wrapper.a" ]; then
  mkdir -p "$OUT"
  cmake -S "$CEF_ROOT" -B "$OUT" -G Ninja -DPROJECT_ARCH=arm64 -DCMAKE_BUILD_TYPE=Release >/dev/null
  ninja -C "$OUT" libcef_dll_wrapper >/dev/null
fi
echo "$OUT"
