#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_KEY_PATH:?Set NOTARY_KEY_PATH to an App Store Connect API key (.p8).}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to the API key ID.}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to the API key issuer ID.}"
: "${SPARKLE_KEY_PATH:?Set SPARKLE_KEY_PATH to the Sparkle EdDSA private key file.}"
identity="${CODESIGN_IDENTITY:-Developer ID Application}"
CODESIGN_IDENTITY="$identity" ./scripts/build-app.sh
app="build/Martin.app"
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
feed="$(plutil -extract SUFeedURL raw "$app/Contents/Info.plist")"
releases="${feed%/latest/download/appcast.xml}"
release="build/release"
dmg="$release/Martin-$version.dmg"
notarize() {
  xcrun notarytool submit "$1" --wait \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  xcrun stapler staple "$2"
}
staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
ditto -c -k --keepParent "$app" "$staging_directory/Martin.zip"
notarize "$staging_directory/Martin.zip" "$app"
spctl --assess --type execute --verbose "$app"
swift scripts/render-dmg-background.swift "$staging_directory/background.tiff"
rm -rf "$release"
mkdir -p "$release"
uvx dmgbuild==1.6.7 -s scripts/dmg-settings.py -D app="$app" -D background="$staging_directory/background.tiff" Martin "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg" "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
app/.build/artifacts/sparkle/Sparkle/bin/generate_appcast "$release" \
  --ed-key-file "$SPARKLE_KEY_PATH" \
  --download-url-prefix "$releases/download/v$version/" \
  --full-release-notes-url "$releases/tag/v$version"
printf 'Released %s\n' "$release"
