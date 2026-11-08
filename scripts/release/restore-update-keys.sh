#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Restores both update signing keys from a backup made by backup-update-keys.sh into the login Keychain (a new Mac,
# or after losing them). Run it yourself in Terminal.app; it asks for the backup's password.
#
#   ./scripts/release/restore-update-keys.sh /Volumes/USB/Nera-update-keys-YYYY-MM-DD.dmg
set -euo pipefail
cd "$(dirname "$0")/../.."
DMG="${1:?usage: restore-update-keys.sh <backup .dmg>}"
KEYCHAIN="${NERA_KEYCHAIN:-}"
expected=$(awk -F'"' '/NeraUpdatePublicKey:/ {print $2; exit}' project.yml)
[ -n "${NERA_EXPECTED_KEYS:-}" ] && expected="$NERA_EXPECTED_KEYS"
if [ -n "${NERA_BACKUP_PASSWORD:-}" ]; then
  MOUNT=$(printf '%s' "$NERA_BACKUP_PASSWORD" | hdiutil attach -stdinpass -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
else
  MOUNT=$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
fi
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true' EXIT
for pair in "current.key:Nera Update Signing Key:${expected%%,*}" "standby.key:Nera Update Signing Key (standby):${expected##*,}"; do
  file="${pair%%:*}"; rest="${pair#*:}"; service="${rest%:*}"; want="${rest##*:}"
  [ "$(swift scripts/release/sign-update.swift public-key < "$MOUNT/$file")" = "$want" ] || { echo "✘ $file doesn't match $want"; exit 1; }
  security add-generic-password -U -s "$service" -a nera -l "$service" -w "$(cat "$MOUNT/$file")" ${KEYCHAIN:+"$KEYCHAIN"}
  echo "✔ restored \"$service\""
done
