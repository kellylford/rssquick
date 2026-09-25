#!/bin/bash
# Signs RSS Quick.app with a Developer ID Application certificate.
#
# Three things have to be true before Apple's notary service will accept a submission: a
# Developer ID signature, the hardened runtime, and a secure timestamp. This does all three.
#
# There are no entitlements, and that is deliberate rather than an omission. Entitlements under
# the hardened runtime are exemptions from it, and this program needs none: it is one Swift
# binary with no nested libraries, it loads no plugins, it runs no third-party code, and it is
# not sandboxed - so reading a local OPML file, fetching feeds and handing a URL to the browser
# all work without asking for anything. Adding an entitlements file here would weaken the
# runtime in exchange for nothing. (Contrast GHManage, whose CPython bundle cannot start without
# four of them.)
#
# Usage:
#   build/sign.sh "path/to/RSS Quick.app"
#
# Environment:
#   RSSQUICK_SIGNING_IDENTITY   Full identity string, e.g.
#                               "Developer ID Application: Kelly Ford (P887QF74N8)".
#                               The first Developer ID Application identity in the keychain is
#                               used when this is unset.
#   RSSQUICK_KEYCHAIN           Keychain to search. CI uses a throwaway one so the signing key
#                               never lands in the login keychain.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: sign.sh <path-to-.app>" >&2
    exit 2
fi

target="$1"
if [[ ! -e "$target" ]]; then
    echo "error: not found: $target" >&2
    exit 1
fi

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
    echo "error: no Developer ID Application identity found." >&2
    echo "       Set RSSQUICK_SIGNING_IDENTITY, or import the certificate first." >&2
    echo "" >&2
    echo "Identities available for signing:" >&2
    security find-identity -v -p codesigning >&2 || true
    exit 1
fi

echo "Signing $target"
echo "  identity: $identity"

# make-app.sh ad-hoc signs the bundle it assembles, because an unsigned binary will not run at
# all on Apple silicon. Removing that signature before re-signing keeps a stale identifier from
# surviving into the Developer ID signature, which notarization would then reject.
codesign --remove-signature ${keychainargs[@]+"${keychainargs[@]}"} "$target" 2>/dev/null || true

codesign --force \
    --options runtime \
    --timestamp \
    ${keychainargs[@]+"${keychainargs[@]}"} \
    --sign "$identity" \
    "$target"

codesign --verify --strict --verbose=2 "$target"

# Gatekeeper's own verdict. Until the build has been notarized this reports rejection, which is
# the expected answer at this point and not a failure.
echo "  Gatekeeper assessment (rejection is expected until notarized):"
spctl --assess --type execute --verbose=2 "$target" 2>&1 || true

echo "Signed $target"
