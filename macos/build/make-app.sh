#!/bin/bash
# Assembles RSSQuick.app around the compiled executable.
#
# There is no Xcode project on purpose. Everything here is a Swift package, which builds with the
# command line tools alone and keeps the whole build readable in one file - the same reasoning
# behind the Windows side's publish.ps1. What an Xcode project would add, this script does: an
# Info.plist, a bundle layout, and the default feed list beside the program.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"
repo="$(dirname "$package")"

configuration="${1:-release}"
universal="${UNIVERSAL:-1}"

# Version lives in VERSION at the repository root and nowhere else, the same as on Windows.
version="$(tr -d '[:space:]' < "$repo/VERSION")"

archflags=()
if [[ "$universal" == "1" ]]; then
    archflags=(--arch arm64 --arch x86_64)
fi

echo "Building rssquick ($configuration)…"
swift build --package-path "$package" -c "$configuration" ${archflags[@]+"${archflags[@]}"}

binary="$(swift build --package-path "$package" -c "$configuration" ${archflags[@]+"${archflags[@]}"} --show-bin-path)/rssquick"
app="$package/artifacts/RSS Quick.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/rssquick"

# The default feed list, shared with the Windows build rather than duplicated.
cp "$repo/src/RSSQuick/RSS.opml" "$app/Contents/Resources/RSS.opml"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RSS Quick</string>
    <key>CFBundleDisplayName</key><string>RSS Quick</string>
    <key>CFBundleExecutable</key><string>rssquick</string>
    <key>CFBundleIdentifier</key><string>com.kellylford.rssquick</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>RSS Quick</string>
</dict>
</plist>
PLIST

# Unsigned builds are refused on Apple silicon, so it is signed here rather than leaving the
# reader with a program that will not open and no explanation. An ad-hoc signature is enough to
# run locally; a release for other people needs a Developer ID and notarisation.
codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1 || {
    echo "warning: could not sign the bundle; it may refuse to open" >&2
}

echo "Built $app (version $version)"
