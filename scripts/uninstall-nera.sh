#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Removes Nera and everything it stores on this Mac: the app, its library (Spaces, tabs, history, bookmarks),
# website data, caches, settings, saved window state, the old sandbox container, and Nera's Keychain items
# (the keys that encrypt its cookies). Other browsers' data is never touched.
#
#   scripts/uninstall-nera.sh            show what will be removed, then ask
#   scripts/uninstall-nera.sh --yes      remove without asking
#   scripts/uninstall-nera.sh --dry-run  only show what would be removed
#   scripts/uninstall-nera.sh --dev      also remove developer leftovers (test and debug builds, CEF download
#                                         cache)
set -uo pipefail

YES=0 DRY=0 DEV=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run|-n) DRY=1 ;;
    --dev) DEV=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)"; exit 2 ;;
  esac
done

IDS=(dev.nera.browser)
[ $DEV = 1 ] && IDS+=(dev.nera.browser.test dev.nera.browser.debug dev.nera.browser.uitests.xctrunner)

L="$HOME/Library"
paths=()
add() { [ -e "$1" ] || [ -L "$1" ] && paths+=("$1"); return 0; }

add "/Applications/Nera.app"
add "$HOME/Applications/Nera.app"
for id in "${IDS[@]}"; do
  add "$L/Application Support/$id"
  add "$L/Caches/$id"
  add "$L/HTTPStorages/$id"
  add "$L/HTTPStorages/$id.binarycookies"
  add "$L/WebKit/$id"
  add "$L/Saved Application State/$id.savedState"
  add "$L/Preferences/$id.plist"
  [ -e "$L/Containers/$id/Data/Library/Application Support/$id" ] && add "$L/Containers/$id"  # old sandboxed builds' library copy
  add "$L/Application Scripts/$id"
done
add "$L/Logs/Nera"
if [ $DEV = 1 ]; then
  add "$L/Caches/Nera"            # CEF downloads used to build Nera from source
fi

keychain=()
for id in "${IDS[@]}"; do
  security find-generic-password -s "Nera Safe Storage ($id)" >/dev/null 2>&1 && keychain+=("Nera Safe Storage ($id)")
done

if [ ${#paths[@]} -eq 0 ] && [ ${#keychain[@]} -eq 0 ]; then
  echo "✔ Nothing to remove: Nera isn't on this Mac."
  exit 0
fi

echo "This removes Nera and all of its data (Spaces, tabs, history, bookmarks, logins and site data):"
for p in "${paths[@]}"; do echo "  • ${p/#$HOME/~}"; done
for k in "${keychain[@]}"; do echo "  • Keychain item \"$k\""; done
echo "Not touched: other browsers, and the shared \"Chromium Safe Storage\" Keychain item."
[ $DRY = 1 ] && { echo "(dry run: nothing removed)"; exit 0; }

if [ $YES = 0 ]; then
  read -r -p "Remove all of this? Type 'yes' to continue: " answer
  [ "$answer" = "yes" ] || { echo "Cancelled. Nothing was removed."; exit 1; }
fi

# Quit Nera (and its Chromium helpers) first, so nothing writes its data back.
osascript -e 'tell application id "dev.nera.browser" to quit' >/dev/null 2>&1
for _ in 1 2 3 4 5; do pgrep -f "Nera.app/Contents/MacOS/Nera" >/dev/null || break; sleep 1; done
pkill -f "Nera.app/Contents/MacOS/Nera" 2>/dev/null
pkill -f "Nera Helper" 2>/dev/null

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
failed=()
for p in "${paths[@]}"; do
  case "$p" in *.app) "$LSREGISTER" -u "$p" >/dev/null 2>&1 ;; esac
  case "$p" in
    */Containers/*)
      # macOS guards the container folder itself; removing the data inside it is what matters.
      id="${p##*/}"
      rm -rf "$p/Data/Library/Application Support/$id" "$p/Data/Library/Caches/$id" 2>/dev/null
      rm -rf "$p" 2>/dev/null
      [ -e "$p/Data/Library/Application Support/$id" ] && failed+=("$p")
      ;;
    *)
      rm -rf "$p" 2>/dev/null
      [ -e "$p" ] && failed+=("$p")
      ;;
  esac
done
for id in "${IDS[@]}"; do defaults delete "$id" >/dev/null 2>&1; done   # also clears the settings cache in memory
for k in "${keychain[@]}"; do
  while security delete-generic-password -s "$k" >/dev/null 2>&1; do :; done
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "⚠ macOS didn't allow removing:"
  for p in $(printf '%s\n' "${failed[@]}" | sort -u); do echo "  • ${p/#$HOME/~}"; done
  echo "Give your terminal Full Disk Access (System Settings ▸ Privacy & Security), then run this again,"
  echo "or drag those folders to the Trash in Finder."
  exit 1
fi
echo "✔ Nera has been removed. Reinstalling starts fresh, with the welcome screen."
