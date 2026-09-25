#!/bin/zsh
# Builds Take for release outside the App Store: archive, sign with the
# Developer ID, zip, and, when a notary profile is named, notarize and staple.
#
#   scripts/release.sh                      # signed zip in dist/
#   NOTARY_PROFILE=Take scripts/release.sh  # also notarized and stapled
#
# The profile is made once with
#   xcrun notarytool store-credentials Take --apple-id <id> --team-id X7AQ5M6X64
# which asks for an app-specific password from appleid.apple.com.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
dist="dist/$version-$build"
archive="$dist/Take.xcarchive"
zip="$dist/Take-$version.zip"
mkdir -p "$dist"

xcodegen generate
xcodebuild -project Take.xcodeproj -scheme Take -configuration Release \
    archive -archivePath "$archive" -quiet
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$dist" -quiet

app="$dist/Take.app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app" 2>/dev/null && echo "Gatekeeper: already accepted" || echo "Gatekeeper: needs notarization"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$app" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    spctl --assess --type execute "$app"
fi
ditto -c -k --keepParent "$app" "$zip"
echo "wrote $zip"
