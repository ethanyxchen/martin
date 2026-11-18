#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_KEY:?Set NOTARY_KEY to the contents of an App Store Connect API key (.p8).}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to the API key ID.}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to the API key issuer ID.}"
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY to the Sparkle EdDSA private key.}"
: "${POSTHOG_PROJECT_TOKEN:?Set POSTHOG_PROJECT_TOKEN to the PostHog project token.}"
: "${SUPABASE_PROJECT_ID:?Set SUPABASE_PROJECT_ID to the Supabase project ID.}"
: "${SUPABASE_KEY:?Set SUPABASE_KEY to the Supabase publishable key.}"
identity="${CODESIGN_IDENTITY:-Developer ID Application}"
CODESIGN_IDENTITY="$identity" ./scripts/build-app.sh
app="build/Martin.app"
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
feed="$(plutil -extract SUFeedURL raw "$app/Contents/Info.plist")"
releases="${feed%/latest/download/appcast.xml}"
release="build/release"
dmg="$release/Martin-$version.dmg"
staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
printf '%s\n' "$NOTARY_KEY" >"$staging_directory/notary.p8"
printf '%s' "$SPARKLE_PRIVATE_KEY" >"$staging_directory/sparkle.key"
notarize() {
  xcrun notarytool submit "$1" --wait \
    --key "$staging_directory/notary.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  xcrun stapler staple "$2"
}
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
  --ed-key-file "$staging_directory/sparkle.key" \
  --download-url-prefix "$releases/download/v$version/" \
  --full-release-notes-url "$releases/tag/v$version"
printf 'Released %s\n' "$release"
