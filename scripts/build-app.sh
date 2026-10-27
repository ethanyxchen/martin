#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$PWD/build/Martin.app"
identity="${CODESIGN_IDENTITY:-Apple Development}"
require_app_stopped() {
  while read -r app_pid; do
    if [[ "$(ps -p "$app_pid" -o comm=)" == "$destination/Contents/MacOS/Martin" ]]; then
      printf 'Quit Martin before replacing its signed app bundle.\n' >&2
      exit 1
    fi
  done < <(pgrep -x Martin || true)
}
require_app_stopped
swift build -c release --package-path app
binary_directory="$(swift build -c release --package-path app --show-bin-path)"
mkdir -p "$PWD/build"
staging_directory="$(mktemp -d "$PWD/build/.martin.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
app_bundle="$staging_directory/Martin.app"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$binary_directory/Martin" "$app_bundle/Contents/MacOS/Martin"
cp app/Resources/Info.plist "$app_bundle/Contents/Info.plist"
version="$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || echo v0.0.0)"
plutil -insert CFBundleShortVersionString -string "${version#v}" "$app_bundle/Contents/Info.plist"
plutil -insert CFBundleVersion -string "${version#v}" "$app_bundle/Contents/Info.plist"
if [[ "$(git rev-parse --absolute-git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]]; then
  worktree="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"
  plutil -replace CFBundleIdentifier -string "dev.ethanchen.martin.$worktree" "$app_bundle/Contents/Info.plist"
  plutil -replace CFBundleName -string "Martin ($worktree)" "$app_bundle/Contents/Info.plist"
  plutil -insert MartinDataDirectory -string "$PWD/.local-app-data" "$app_bundle/Contents/Info.plist"
fi
plutil -lint "$app_bundle/Contents/Info.plist"
codesign --force --options runtime --timestamp --entitlements app/Resources/Martin.entitlements --sign "$identity" "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
require_app_stopped
rm -rf "$destination"
mv "$app_bundle" "$destination"
printf 'Built %s\n' "$destination"
