#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# A11Y-009: checks that assistive apps can read web pages in Nera, on both engines, the way VoiceOver reads them
# (from outside the app, through the accessibility API). Also checks that an assistive app appearing mid-session gets
# Nera to offer a restart (Chromium exposes pages only when it starts with accessibility).
# Needs Accessibility permission for this terminal, and a Debug build with the test bundle ID:
#   xcodebuild ... NERA_APP_BUNDLE_ID=dev.nera.browser.test build
# Usage: check-screen-readers.sh [path/to/Nera.app]   (opens windows for about two minutes)
set -eu
APP="$(cd "$(dirname "${1:-build/DerivedData/Build/Products/Debug/Nera.app}")" && pwd)/$(basename "${1:-Nera.app}")"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = dev.nera.browser.test ] || {
    echo "✘ build with NERA_APP_BUNDLE_ID=dev.nera.browser.test (never touch the real Nera)"; exit 1; }
WORK="$(mktemp -d)"
PREFS="$HOME/Library/Preferences/dev.nera.browser.test"
trap 'pkill -f "$APP/Contents/MacOS/Nera" 2>/dev/null; defaults delete "$PREFS" NeraWebAccessibility 2>/dev/null; rm -rf "$WORK"' EXIT
swiftc -O "$(dirname "$0")/ax-tool.swift" -o "$WORK/ax-tool"
printf '<!doctype html><title>Readable Page</title><h1>Nera heading</h1><p>Readable paragraph</p><button>Press me</button>' >"$WORK/page.html"
failed=0

launch() {  # engine
    pkill -f "$APP/Contents/MacOS/Nera" 2>/dev/null || true
    sleep 1
    open -n --env NERA_UI_TEST=1 --env NERA_ENGINE="$1" "$APP"
    sleep 15
    PID=$(pgrep -f "$APP/Contents/MacOS/Nera" | head -1)
}

readable() {  # engine
    launch "$1"
    open -a "$APP" "$WORK/page.html"  # opens in a Little Window
    sleep 8
    "$WORK/ax-tool" press "$PID" "Open in Nera" || true
    sleep 6
    echo "$1 page:"
    "$WORK/ax-tool" read "$PID" "Nera heading" "Readable paragraph" "Press me" || failed=1
}

defaults write "$PREFS" NeraWebAccessibility -bool YES
readable chromium
defaults delete "$PREFS" NeraWebAccessibility
readable webkit

launch chromium
echo "assistive app appears mid-session:"
"$WORK/ax-tool" flag "$PID" AXManualAccessibility || failed=1
"$WORK/ax-tool" read "$PID" "Restart Nera so assistive apps can read pages" || failed=1
[ "$(defaults read "$PREFS" NeraWebAccessibility 2>/dev/null)" = 1 ] && echo "  ✔ remembered for the next start" || { echo "  ✘ not remembered"; failed=1; }

[ $failed = 0 ] && echo "✔ screen readers can read pages on both engines" || echo "✘ screen reader check failed"
exit $failed
