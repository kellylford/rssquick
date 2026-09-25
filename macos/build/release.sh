#!/bin/bash
# Produces the signed, notarized, stapled RSS Quick disk image - the whole release in one run.
#
#   tests -> universal app -> Developer ID signature -> notarize and staple the app
#         -> disk image -> sign the image -> notarize and staple the image -> verify
#
# The app and the image are notarized separately, which means two round trips to Apple and so
# roughly five to thirty minutes. Both are worth paying for. Notarizing the image is what stops
# Gatekeeper warning on the download; stapling the app is what keeps it valid after a reader has
# dragged it to Applications and deleted the image, with no network to ask Apple over.
#
# This fails closed. If any step fails there is no artefact to publish, which is the point - a
# half-signed build is worse than none, because it looks finished.
#
# Usage:
#   build/release.sh                Full run.
#   build/release.sh --no-notarize  Sign only. For checking the signing setup without waiting on
#                                   Apple; the result must not be published.
#   build/release.sh --no-test      Skip the test suite. For re-running a failed notarization.
#
# Credentials: see sign.sh for the certificate and notarize.sh for the API key.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"
repo="$(dirname "$package")"

notarize=1
runtests=1
for arg in "$@"; do
    case "$arg" in
        --no-notarize) notarize=0 ;;
        --no-test)     runtests=0 ;;
        *) echo "usage: release.sh [--no-notarize] [--no-test]" >&2; exit 2 ;;
    esac
done

version="$(tr -d '[:space:]' < "$repo/VERSION")"
app="$package/artifacts/RSS Quick.app"
dmg="$package/artifacts/RSSQuick-$version-macos.dmg"

echo "Releasing RSS Quick $version for macOS"
echo ""

if [[ "$runtests" == "1" ]]; then
    echo "── Tests ───────────────────────────────────────────────────────────────"
    swift test --package-path "$package"
    echo ""
fi

echo "── Building the universal app ───────────────────────────────────────────"
"$here/make-app.sh" release
echo ""

echo "── Signing ──────────────────────────────────────────────────────────────"
"$here/sign.sh" "$app"
echo ""

if [[ "$notarize" == "1" ]]; then
    echo "── Notarizing the app ───────────────────────────────────────────────────"
    "$here/notarize.sh" "$app"
    echo ""
fi

echo "── Disk image ───────────────────────────────────────────────────────────"
"$here/make-dmg.sh" "$app"
echo ""

if [[ "$notarize" == "1" ]]; then
    echo "── Notarizing the image ─────────────────────────────────────────────────"
    "$here/notarize.sh" "$dmg"
    echo ""

    echo "── Verifying ────────────────────────────────────────────────────────────"
    # --context context:primary-signature is what Gatekeeper uses for a downloaded disk image.
    # Without it spctl assesses the image as though it were being executed, and reports a
    # rejection that says nothing about how the reader's Mac will treat it.
    spctl --assess --type open --context context:primary-signature -v "$dmg"
    spctl --assess --type execute -v "$app"
    echo ""
fi

echo "════════════════════════════════════════════════════════════════════════"
if [[ "$notarize" == "1" ]]; then
    echo "Ready to publish: $dmg"
else
    echo "Signed but NOT notarized: $dmg"
    echo "Gatekeeper will refuse this after a download. Do not publish it."
fi
echo "════════════════════════════════════════════════════════════════════════"
