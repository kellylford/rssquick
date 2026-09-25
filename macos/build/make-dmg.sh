#!/bin/bash
# Builds the drag-to-Applications disk image around an already-signed RSS Quick.app.
#
# The app must be signed, notarized and stapled before this runs. release.sh does it in that
# order, and the order matters: an app stapled first stays valid after a reader drags it out of
# the image and throws the image away, which is the normal thing to do with a DMG.
#
# The image itself is signed and notarized separately, because Gatekeeper assesses the file the
# reader downloaded. An unnotarized image warns on open even when the app inside it is perfect.
#
# Usage:
#   build/make-dmg.sh "path/to/RSS Quick.app"
#
# Environment: RSSQUICK_SIGNING_IDENTITY and RSSQUICK_KEYCHAIN, as in sign.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"
repo="$(dirname "$package")"

if [[ $# -ne 1 ]]; then
    echo "usage: make-dmg.sh <path-to-.app>" >&2
    exit 2
fi

app="$1"
if [[ ! -d "$app" ]]; then
    echo "error: not found: $app" >&2
    exit 1
fi

version="$(tr -d '[:space:]' < "$repo/VERSION")"
volume="RSS Quick $version"
mount="/Volumes/$volume"
dmg="$package/artifacts/RSSQuick-$version-macos.dmg"

staging="$(mktemp -d)"
tempro="$(mktemp -u).dmg"
temprw="$(mktemp -u).dmg"
trap 'rm -rf "$staging" "$tempro" "$temprw"' EXIT

echo "Staging $volume…"
cp -a "$app" "$staging/"

# A plain-text readme rather than a background image with arrows in it. The window art that most
# DMGs use to say "drag this there" is invisible to VoiceOver, so the instruction has to exist as
# text for it to exist at all.
cat > "$staging/Read Me.txt" <<READ
RSS Quick $version for macOS

To install, drag RSS Quick to the Applications folder in this window, then open
it from Applications or Launchpad.

RSS Quick is signed and notarized by Apple, so it opens without any security
prompt and without needing to be allowed in System Settings.

WHAT IT IS

  A keyboard-driven RSS reader built for VoiceOver and braille display users.
  Two panes: feeds on the left, headlines on the right. Articles open in your
  browser.

  Tab and Shift-Tab move between the panes. Arrow keys move within one. Return
  loads the selected feed, or opens the selected headline.

FEEDS

  A starter feed list is built in. File > Import OPML replaces it with your own
  at any time.

REQUIREMENTS

  macOS 13 Ventura or newer, on either Apple silicon or Intel.

https://github.com/kellylford/rssquick
READ

rm -f "$dmg"
mkdir -p "$package/artifacts"

# The /Applications symlink goes onto the mounted read-write image rather than into the staging
# folder. `hdiutil create -srcfolder` follows symlinks, so a link to /Applications sitting in
# staging makes it try to copy the whole of the real /Applications, and the build fails.
hdiutil detach "$mount" 2>/dev/null || true

# hdiutil prints a deprecation notice on macOS 26 and later, pointing at `diskutil image`.
# The deprecated spelling is kept deliberately: diskutil grew those subcommands in macOS 26,
# and this has to keep building on the older runners and Macs that macOS 13 support implies.
echo "Creating the image…"
hdiutil create -srcfolder "$staging" -volname "$volume" \
    -fs HFS+ -format UDZO -imagekey zlib-level=1 "$tempro" >/dev/null

hdiutil convert "$tempro" -format UDRW -o "$temprw" >/dev/null
rm -f "$tempro"

hdiutil attach -readwrite -noverify -noautoopen "$temprw" >/dev/null
if [[ ! -d "$mount" ]]; then
    echo "error: the image did not mount at $mount" >&2
    exit 1
fi

ln -s /Applications "$mount/Applications"
sync
hdiutil detach "$mount" -force >/dev/null

echo "Compressing…"
hdiutil convert "$temprw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null

keychainargs=()
if [[ -n "${RSSQUICK_KEYCHAIN:-}" ]]; then
    keychainargs=(--keychain "$RSSQUICK_KEYCHAIN")
fi

identity="${RSSQUICK_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning ${RSSQUICK_KEYCHAIN:+"$RSSQUICK_KEYCHAIN"} \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')" || true
fi

if [[ -z "$identity" ]]; then
    echo "error: no Developer ID Application identity found to sign the image with." >&2
    exit 1
fi

echo "Signing the image…"
codesign --force --timestamp ${keychainargs[@]+"${keychainargs[@]}"} --sign "$identity" "$dmg"
codesign --verify --verbose "$dmg"

echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
