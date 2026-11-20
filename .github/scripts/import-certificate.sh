#!/bin/bash
set -euo pipefail
: "${DEVELOPER_ID_P12:?Set DEVELOPER_ID_P12 to the base64 Developer ID certificate.}"
: "${DEVELOPER_ID_P12_PASSWORD:?Set DEVELOPER_ID_P12_PASSWORD to its password.}"
keychain="$RUNNER_TEMP/signing.keychain-db"
password="$(uuidgen)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
base64 --decode <<<"$DEVELOPER_ID_P12" >"$RUNNER_TEMP/developer-id.p12"
security import "$RUNNER_TEMP/developer-id.p12" -k "$keychain" \
  -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
rm "$RUNNER_TEMP/developer-id.p12"
security set-key-partition-list -S apple-tool:,apple: -k "$password" "$keychain"
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
identity="$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ { print $2; exit }')"
[ -n "$identity" ] || { echo "No Developer ID Application identity in the imported certificate" >&2; exit 1; }
echo "CODESIGN_IDENTITY=$identity" >>"$GITHUB_ENV"
