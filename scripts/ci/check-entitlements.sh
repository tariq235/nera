#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Per-bundle entitlement gate for the macOS app (SEC-050/051/052/074; ADR-0006, ADR-0009).
# - Every bundle (app, Chromium helpers, CEF framework) is signed with the hardened runtime.
# - Each bundle holds only its reviewed entitlements; the forbidden ones never appear anywhere.
# - The main app runs without the App Sandbox (Chromium's browser process needs what it denies); web
#   content is sandboxed by the engines. Adding an entitlement needs an ADR + a reviewer.
set -euo pipefail
APP="${1:-build/DerivedData/Build/Products/Release/Nera.app}"
[ -d "$APP" ] || { echo "skip: $APP not built"; exit 0; }

FORBIDDEN="com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.disable-executable-page-protection com.apple.security.cs.allow-dyld-environment-variables"
MAIN_ALLOWED="com.apple.security.device.camera com.apple.security.device.audio-input com.apple.security.personal-information.location com.apple.security.get-task-allow com.apple.developer.web-browser.public-key-credential com.apple.application-identifier com.apple.developer.team-identifier"
RENDERER_ALLOWED="com.apple.security.cs.allow-jit"

entitlements() {  # one enabled entitlement per line; nothing if the bundle has none
  local xml
  xml="$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)"
  [ -n "$xml" ] || return 0
  plutil -convert json -o - - <<< "$xml" | python3 -I -c 'import json,sys; print("\n".join(k for k,v in json.load(sys.stdin).items() if v))'
}

fail=0
check() {  # bundle, allowed list
  local bundle="$1" allowed="$2" name e
  name="$(basename "$bundle")"
  local sig
  sig="$(codesign -dv "$bundle" 2>&1 || true)"   # captured first: grep -q on a live pipe trips pipefail
  grep -q 'flags=.*runtime' <<< "$sig" || { echo "✘ $name: hardened runtime missing"; fail=1; }
  while read -r e; do
    [ -z "$e" ] && continue
    if grep -qw -- "$e" <<< "$FORBIDDEN"; then echo "✘ $name: forbidden entitlement $e"; fail=1; continue; fi
    grep -qw -- "$e" <<< "$allowed" || { echo "✘ $name: unreviewed entitlement $e (add via ADR)"; fail=1; }
  done <<< "$(entitlements "$bundle")"
}

check "$APP" "$MAIN_ALLOWED"
FW="$APP/Contents/Frameworks"
helpers=0
for h in "$FW"/*Helper*.app; do
  [ -d "$h" ] || continue
  helpers=$((helpers + 1))
  case "$h" in *"(Renderer).app") check "$h" "$RENDERER_ALLOWED" ;; *) check "$h" "" ;; esac
done
[ -d "$FW/Chromium Embedded Framework.framework" ] && check "$FW/Chromium Embedded Framework.framework" ""
[ "$helpers" -eq 5 ] || { echo "✘ expected 5 Chromium helpers, found $helpers"; fail=1; }
codesign --verify --deep --strict "$APP" 2>/dev/null || { echo "✘ codesign --verify --deep --strict failed"; fail=1; }
[ $fail -eq 0 ] && echo "✔ entitlements OK (app + $helpers helpers + CEF framework; hardened runtime everywhere)"
exit $fail
