#!/bin/zsh
# Builds Take for the Mac App Store: archive, export a signed installer
# package, and, with UPLOAD=1, send it to App Store Connect.
#
#   scripts/appstore.sh           # signed Take.pkg under dist/
#   UPLOAD=1 scripts/appstore.sh  # also uploads; needs the app record to exist
#
# Signing is automatic through the Apple ID signed into Xcode; the
# distribution certificate and the store profile are minted on demand.
# The upload needs an app record for com.siddharthnigam.take in App Store
# Connect; make it once on the web.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
dist="dist/$version-$build"
archive="$dist/Take.xcarchive"
mkdir -p "$dist/appstore"

xcodegen generate
xcodebuild -project Take.xcodeproj -scheme Take -configuration Release \
    archive -archivePath "$archive" -quiet
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
    -exportPath "$dist/appstore" -allowProvisioningUpdates -quiet
pkgutil --check-signature "$dist/appstore/Take.pkg" | head -3
echo "wrote $dist/appstore/Take.pkg"

if [[ "${UPLOAD:-0}" = "1" ]]; then
    options=$(mktemp -t take-upload).plist
    sed 's|<string>export</string>|<string>upload</string>|' scripts/ExportOptions-AppStore.plist > "$options"
    xcodebuild -exportArchive -archivePath "$archive" \
        -exportOptionsPlist "$options" -exportPath "$dist/upload" -allowProvisioningUpdates
    echo "uploaded $version ($build) to App Store Connect"
fi
