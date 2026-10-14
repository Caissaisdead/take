#!/bin/zsh
# Builds Take for the App Store: archive, export a signed package, and,
# with UPLOAD=1, send it to App Store Connect. The Mac by default; the
# iPhone with PLATFORM=ios.
#
#   scripts/appstore.sh                # signed Take.pkg under dist/
#   PLATFORM=ios scripts/appstore.sh   # signed Take.ipa under dist/
#   UPLOAD=1 scripts/appstore.sh       # also uploads; needs the app record to exist
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
if [[ "${PLATFORM:-mac}" = "ios" ]]; then
    scheme=TakeMobile
    destination=(-destination generic/platform=iOS)
    archive="$dist/TakeMobile.xcarchive"
    out="$dist/appstore-ios"
    product="$out/Take.ipa"
else
    scheme=Take
    destination=()
    archive="$dist/Take.xcarchive"
    out="$dist/appstore"
    product="$out/Take.pkg"
fi
mkdir -p "$out"

xcodegen generate
xcodebuild -project Take.xcodeproj -scheme "$scheme" -configuration Release \
    "${destination[@]}" archive -archivePath "$archive" -allowProvisioningUpdates -quiet
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
    -exportPath "$out" -allowProvisioningUpdates -quiet
if [[ "$product" = *.pkg ]]; then
    pkgutil --check-signature "$product" | head -3
else
    unzip -l "$product" | tail -1
fi
echo "wrote $product"

if [[ "${UPLOAD:-0}" = "1" ]]; then
    plist=$(mktemp -t take-upload).plist
    sed 's|<string>export</string>|<string>upload</string>|' scripts/ExportOptions-AppStore.plist > "$plist"
    xcodebuild -exportArchive -archivePath "$archive" \
        -exportOptionsPlist "$plist" -exportPath "$dist/upload" -allowProvisioningUpdates
    echo "uploaded $version ($build) to App Store Connect"
fi
