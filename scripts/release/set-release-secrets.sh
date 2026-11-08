#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Puts the release signing secrets into the repository's `release` environment (docs/release-pipeline.md), straight
# from this Mac, without showing any of them. Run it yourself in Terminal.app; macOS asks for permission to read each
# Keychain item, and to export the Developer ID private key:
#
#   ./scripts/release/set-release-secrets.sh <AuthKey_XXXXXXXXXX.p8> <issuer ID> [key ID]
#
# The .p8 is an App Store Connect API key for notarization (App Store Connect › Users and Access › Integrations ›
# Team Keys, role "Developer"); the key ID and issuer ID are shown on that page. The script checks every secret before
# uploading it: the Developer ID certificate and its key belong together, the update key matches the public key built
# into the app, and Apple accepts the notarization key. Run it again to replace the secrets (e.g. after a rotation).
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 2 ] && [ $# -le 3 ] || { sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
P8="$1"; KEY_ID=""; ISSUER=""
# The issuer ID is a UUID and the key ID is ten characters (also in the file name), so the order doesn't matter.
uuid='^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$'
for arg in "${@:2}"; do if [[ $arg =~ $uuid ]]; then ISSUER="$arg"; else KEY_ID="$arg"; fi; done
name=$(basename "$P8"); [[ $name =~ ^AuthKey_([A-Z0-9]{10})\.p8$ ]] && KEY_ID="${KEY_ID:-${BASH_REMATCH[1]}}"
[ -n "$ISSUER" ] || { echo "✘ the issuer ID (a UUID, shown above the keys in App Store Connect) is missing"; exit 1; }
[ -n "$KEY_ID" ] || { echo "✘ the key ID is missing"; exit 1; }
REPO="${NERA_REPO:-tariq235/nera}"
[ -f "$P8" ] || { echo "✘ $P8 not found"; exit 1; }
umask 077
openssl() { /usr/bin/openssl "$@"; }   # LibreSSL: its .p12 format is the one `security import` reads
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
put() { gh secret set "$1" --env release -R "$REPO" >/dev/null && echo "✔ $1"; }   # value on stdin

echo "1/4 Notarization key: asking Apple to accept it…"
xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null \
  || { echo "✘ Apple rejected the key (check the key ID, the issuer ID and the key's role)"; exit 1; }

echo "2/4 Developer ID certificate: exporting it with its private key only…"
identity=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' | sort -u)
[ "$(printf '%s\n' "$identity" | grep -c .)" = 1 ] || { echo "✘ expected one Developer ID Application identity, found: ${identity:-none}"; exit 1; }
EXPORT_PW=$(openssl rand -hex 24); P12_PW=$(openssl rand -hex 24); export EXPORT_PW P12_PW
# `security export` takes every identity in the keychain; keep only the Developer ID certificate and its own key.
security export -k login.keychain-db -t identities -f pkcs12 -P "$EXPORT_PW" -o "$TMP/all.p12"
openssl pkcs12 -in "$TMP/all.p12" -passin env:EXPORT_PW -nodes -out "$TMP/all.pem" 2>/dev/null
python3 -I - "$TMP" "$identity" <<'PY'
import re, sys
tmp, name = sys.argv[1], sys.argv[2]
blocks = re.findall(r"(Bag Attributes.*?)(-----BEGIN (CERTIFICATE|PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY)-----.*?-----END \3-----)",
                    open(f"{tmp}/all.pem").read(), re.S)
key_id = lambda attrs: (re.search(r"localKeyID: ([0-9A-F ]+)", attrs) or [None, None])[1]
certs = [(key_id(a), pem) for a, pem, kind in blocks if kind == "CERTIFICATE" and name in a]
if len(certs) != 1 or certs[0][0] is None:
    sys.exit("✘ couldn't find the Developer ID certificate in the export")
keys = [pem for a, pem, kind in blocks if kind != "CERTIFICATE" and key_id(a) == certs[0][0]]
if len(keys) != 1:
    sys.exit("✘ couldn't find the Developer ID private key in the export")
open(f"{tmp}/cert.pem", "w").write(certs[0][1] + "\n")
open(f"{tmp}/key.pem", "w").write(keys[0] + "\n")
PY
[ "$(openssl x509 -in "$TMP/cert.pem" -noout -pubkey | openssl sha256)" = "$(openssl pkey -in "$TMP/key.pem" -pubout | openssl sha256)" ] \
  || { echo "✘ the certificate and the key don't match"; exit 1; }
openssl pkcs12 -export -in "$TMP/cert.pem" -inkey "$TMP/key.pem" -name "$identity" -passout env:P12_PW -out "$TMP/devid.p12"
openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate | sed 's/^/    /'

echo "3/4 Update signing key: checking it against the app's public key…"
current=$(awk -F'"' '/NeraUpdatePublicKey:/ {print $2; exit}' project.yml | cut -d, -f1)
[ "$(security find-generic-password -s "Nera Update Signing Key" -a nera -w | swift scripts/release/sign-update.swift public-key)" = "$current" ] \
  || { echo "✘ the Keychain's update key isn't the current key in project.yml"; exit 1; }

echo "4/4 Uploading to $REPO › release…"
base64 -i "$TMP/devid.p12" | put DEVELOPER_ID_CERT_P12
printf %s "$P12_PW" | put DEVELOPER_ID_CERT_PASSWORD
printf %s "$KEY_ID" | put AC_API_KEY_ID
printf %s "$ISSUER" | put AC_API_ISSUER_ID
put AC_API_KEY_P8 < "$P8"
security find-generic-password -s "Nera Update Signing Key" -a nera -w | tr -d '\n' | put SPARKLE_ED_PRIVATE_KEY
if security find-generic-password -s "Nera Safe Browsing Key" -a nera >/dev/null 2>&1; then
  security find-generic-password -s "Nera Safe Browsing Key" -a nera -w | tr -d '\n' | put SAFE_BROWSING_KEY
else
  echo "– no Safe Browsing key in the Keychain; releases will ship without phishing protection"
fi
echo "Done. Delete $P8 once it is backed up (Apple lets you download it only once)."
