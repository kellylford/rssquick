#!/usr/bin/env bash
#
# release-testflight.sh <build-number> — archive RSS Quick for iOS and upload it to TestFlight.
#
# The marketing version comes from VERSION at the repository root, the same file the Windows and
# macOS builds read. The build number must be one App Store Connect has not seen before for that
# version, including builds it rejected.
#
# Signing and upload both use the Apple ID signed in to Xcode (Settings -> Accounts), with
# automatic signing, so there are no keys to set up for a local release. Once App Store Connect
# has processed the build (5-15 minutes) it is available to the "Internal" TestFlight group.
#
# Usage:
#   scripts/release-testflight.sh 2
#   scripts/release-testflight.sh 2 --export-only    (write an .ipa, don't upload)
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios="$(cd "$here/.." && pwd)"
repo="$(cd "$ios/.." && pwd)"

build="${1:-}"
[[ "$build" =~ ^[0-9]+$ ]] || { echo "usage: release-testflight.sh <build-number> [--export-only]" >&2; exit 2; }
mode="${2:-upload}"

version="$(tr -d '[:space:]' < "$repo/VERSION")"
out="$ios/build/release"
archive="$out/RSSQuick-$version-$build.xcarchive"
export_dir="$out/export-$version-$build"
rm -rf "$archive" "$export_dir"
mkdir -p "$out"

echo "▶ Archiving RSS Quick $version ($build)"
xcodebuild \
    -project "$ios/RSSQuick.xcodeproj" \
    -scheme RSSQuick \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build" \
    clean archive

# The committed plist exports an .ipa. Uploading is the same plist with one key changed, so the
# two can never disagree about anything else.
plist="$out/ExportOptions.plist"
cp "$here/ExportOptions.plist" "$plist"
if [[ "$mode" != "--export-only" ]]; then
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$plist"
    echo "▶ Uploading to App Store Connect"
else
    echo "▶ Exporting .ipa"
fi

xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$plist" \
    -allowProvisioningUpdates

echo ""
if [[ "$mode" == "--export-only" ]]; then
    echo "✅ Exported: $(find "$export_dir" -maxdepth 1 -name '*.ipa' | head -1)"
else
    echo "✅ Uploaded $version ($build). App Store Connect is processing it; TestFlight will email"
    echo "   the Internal group when it is ready, usually within 15 minutes."
fi
