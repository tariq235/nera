#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Backs up both update signing keys (docs/release/update-signing-key.md) into an AES-256 encrypted disk image, without
# showing them. Run it yourself in Terminal.app (it asks for a new password for the image, then for permission to
# read the two Keychain items):
#
#   cd <your clone of the repository> && ./scripts/release/backup-update-keys.sh [folder]     (default: ~/Desktop)
#
# Then copy the .dmg to a USB drive kept away from this Mac (ideally two), and keep its password in Apple Passwords
# and on paper. Restore with restore-update-keys.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:-$HOME/Desktop}"
KEYCHAIN="${NERA_KEYCHAIN:-}"   # tests use a throwaway keychain; normally the login keychain
DMG="$OUT/Nera-update-keys-$(date +%Y-%m-%d).dmg"
umask 077

expected=$(awk -F'"' '/NeraUpdatePublicKey:/ {print $2; exit}' project.yml)   # "current,standby"
[ -n "${NERA_EXPECTED_KEYS:-}" ] && expected="$NERA_EXPECTED_KEYS"
want_current="${expected%%,*}"; want_standby="${expected##*,}"

read_key() { security find-generic-password -s "$1" -a nera -w ${KEYCHAIN:+"$KEYCHAIN"}; }
public_of() { swift scripts/release/sign-update.swift public-key; }

echo "→ checking the Keychain keys match the public keys built into Nera"
[ "$(read_key "Nera Update Signing Key" | public_of)" = "$want_current" ] || { echo "✘ current key doesn't match"; exit 1; }
[ "$(read_key "Nera Update Signing Key (standby)" | public_of)" = "$want_standby" ] || { echo "✘ standby key doesn't match"; exit 1; }
echo "✔ both keys match"

[ -e "$DMG" ] && { echo "✘ $DMG already exists"; exit 1; }
echo "→ creating the encrypted disk image: choose a strong password and keep it safe"
if [ -n "${NERA_BACKUP_PASSWORD:-}" ]; then  # tests only
  printf '%s' "$NERA_BACKUP_PASSWORD" | hdiutil create -quiet -size 8m -fs APFS -volname "Nera update keys" -encryption AES-256 -stdinpass "$DMG"
  MOUNT=$(printf '%s' "$NERA_BACKUP_PASSWORD" | hdiutil attach -stdinpass -nobrowse "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
else
  hdiutil create -quiet -size 8m -fs APFS -volname "Nera update keys" -encryption AES-256 "$DMG"
  MOUNT=$(hdiutil attach -nobrowse "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
fi
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true' EXIT

read_key "Nera Update Signing Key" > "$MOUNT/current.key"
read_key "Nera Update Signing Key (standby)" > "$MOUNT/standby.key"
cat > "$MOUNT/README.txt" <<TXT
Nera update signing keys, backed up $(date +%Y-%m-%d).
current.key  → Keychain item "Nera Update Signing Key" (public key $want_current)
standby.key  → Keychain item "Nera Update Signing Key (standby)" (public key $want_standby)
Restore: scripts/release/restore-update-keys.sh <this .dmg>
Never paste these keys into a chat, an issue or a repository.
TXT

echo "→ verifying the copies"
[ "$(public_of < "$MOUNT/current.key")" = "$want_current" ] && [ "$(public_of < "$MOUNT/standby.key")" = "$want_standby" ] \
  || { echo "✘ the copies don't match: delete $DMG and try again"; exit 1; }
hdiutil detach -quiet "$MOUNT"; trap - EXIT
echo "✔ backup written and verified: $DMG"
echo "  Next: copy it to a USB drive (ideally two), keep the password in Apple Passwords and on paper,"
echo "  then delete the copy on this Mac's Desktop. Tell Claude the date so it's recorded."
