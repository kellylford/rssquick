#!/bin/bash
# Submits an artefact to Apple's notary service, waits for the verdict, and staples the ticket.
#
# Stapling is the part worth insisting on. Without a stapled ticket macOS asks Apple whether the
# download is notarized the first time it runs, so a reader opening RSS Quick on a plane, or
# behind a firewall that blocks Apple's endpoints, is told the app cannot be verified. Stapling
# writes the answer into the artefact, and it validates offline from then on.
#
# stapler works on a .app and on a .dmg, but not on a .zip. A zip carries a ticket only by way
# of the .app inside it having been stapled before it was zipped.
#
# Usage:
#   build/notarize.sh "path/to/RSS Quick.app"
#   build/notarize.sh artifacts/RSSQuick-1.2.0-macos.dmg
#
# Credentials - an App Store Connect API key is the expected form, and the only one that works
# without interaction in CI. A stored keychain profile is accepted too, since it is the same
# credential by another route. Tried in this order:
#
#   NOTARY_KEY_PATH     Path to AuthKey_XXXXXXXXXX.p8
#   NOTARY_KEY_ID       The 10-character Key ID
#   NOTARY_ISSUER_ID    The issuer UUID from App Store Connect
#
#   NOTARY_PROFILE      Profile name stored by `notarytool store-credentials`
#   NOTARY_KEYCHAIN     Optional keychain holding it
#
# These names match scripts/notarize_macos.sh in GHManage on purpose, so one set of exported
# variables covers both repositories.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: notarize.sh <path-to-.app-or-.dmg-or-.zip>" >&2
    exit 2
fi

target="$1"
if [[ ! -e "$target" ]]; then
    echo "error: not found: $target" >&2
    exit 1
fi

credargs=()
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    if [[ ! -f "$NOTARY_KEY_PATH" ]]; then
        echo "error: NOTARY_KEY_PATH is set but there is no file there: $NOTARY_KEY_PATH" >&2
        exit 1
    fi
    echo "Using the App Store Connect API key (key id $NOTARY_KEY_ID)"
    credargs=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Using the notarytool keychain profile $NOTARY_PROFILE"
    credargs=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
        credargs+=(--keychain "$NOTARY_KEYCHAIN")
    fi

else
    cat >&2 <<'USAGE'
error: no notarization credentials.

Set either

  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID    an App Store Connect API key

or

  NOTARY_PROFILE                                        a stored notarytool profile

See the signing section of macos/README.md for how to obtain the key.
USAGE
    exit 1
fi

# A bare .app cannot be submitted; the notary service takes an archive. ditto is the right tool
# rather than zip, because it preserves the extended attributes and symlinks that make up a
# bundle's code signature - a zip(1) archive of a .app arrives with the signature broken.
submission="$target"
scratch=""
if [[ -d "$target" && "$target" == *.app ]]; then
    scratch="$(mktemp -d)"
    submission="$scratch/$(basename "$target").zip"
    echo "Archiving the bundle for submission…"
    ditto -c -k --keepParent "$target" "$submission"
fi

cleanup() { [[ -n "$scratch" ]] && rm -rf "$scratch"; return 0; }
trap cleanup EXIT

echo "Submitting $(basename "$submission") to Apple. This usually takes 2-15 minutes."

log="$(mktemp)"
trap 'cleanup; rm -f "$log"' EXIT

# notarytool's exit status is deliberately ignored here. A rejection still prints the submission
# id, and that id is the only way to fetch the log naming the binary Apple objected to. The
# status line below is what decides success.
xcrun notarytool submit "$submission" ${credargs[@]+"${credargs[@]}"} --wait 2>&1 | tee "$log" || true

if ! grep -q "status: Accepted" "$log"; then
    echo "" >&2
    echo "Notarization failed." >&2
    id="$(grep -Eo '\bid: [0-9a-f-]{36}' "$log" | head -1 | awk '{print $2}')" || true
    if [[ -n "${id:-}" ]]; then
        echo "Fetching the detailed log for submission $id - it names the offending binary," >&2
        echo "which the summary above does not." >&2
        xcrun notarytool log "$id" ${credargs[@]+"${credargs[@]}"} >&2 || true
    fi
    exit 1
fi

echo "Notarization accepted. Stapling the ticket…"

# The ticket is stapled to the original artefact, not to the zip that was submitted. That is the
# whole point of doing it this way for a .app: the zip is scaffolding and gets thrown away.
xcrun stapler staple "$target"
xcrun stapler validate "$target"

echo "Notarized and stapled $target"
