#!/bin/bash
# One-time: loads the five repository secrets macos-release.yml needs to sign and notarise the
# disk image, so a pushed tag builds the Mac release with no Mac involved.
#
# You run this, not an agent, so the private key and its password never leave this machine. It
# finds everything it needs locally:
#
#   Developer ID Application certificate   the login keychain
#   Notary key, key id and issuer id       ~/.fastweather-keys/asc.json
#
# That is the same arrangement, and the same five secret names, as Image-Description-Toolkit and
# GHManage (whose scripts/setup_macos_secrets.sh this is adapted from). GitHub never reveals a
# secret once set, so they cannot be copied from one repository to another; each is set from the
# same local files.
#
# Usage:
#   build/setup-ci-secrets.sh                 # export the certificate from the keychain
#   build/setup-ci-secrets.sh path/to.p12     # use a .p12 you already have
#
# The keychain export puts up one macOS dialog asking you to allow it. That is the only
# interactive step: the export password is generated here and stored as
# MACOS_CERTIFICATE_PASSWORD, and nobody needs to remember it.

set -euo pipefail

ASC_JSON="$HOME/.fastweather-keys/asc.json"
IDENTITY="Developer ID Application: Kelly Ford (P887QF74N8)"

die() { echo "error: $*" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
    [ -n "${VERIFY_KC:-}" ] && security delete-keychain "$VERIFY_KC" 2>/dev/null || true
}
trap cleanup EXIT

# Preflight

command -v gh >/dev/null || die "gh CLI not found."
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

# The repository this checkout belongs to, rather than a name written in here that could drift.
REPO="$(cd "$here" && gh repo view --json nameWithOwner -q .nameWithOwner)" \
    || die "could not tell which GitHub repository this is."

[ -f "$ASC_JSON" ] || die "missing $ASC_JSON - the notary key id and issuer id live there."

security find-identity -v -p codesigning | grep -q "$IDENTITY" \
    || die "'$IDENTITY' is not in the login keychain. Download it from developer.apple.com."

KEY_ID="$(python3 -c "import json;print(json.load(open('$ASC_JSON'))['key_id'])")"
ISSUER="$(python3 -c "import json;print(json.load(open('$ASC_JSON'))['issuer_id'])")"
P8="$(python3 -c "import json,os;print(os.path.expanduser(json.load(open('$ASC_JSON'))['p8_path']))")"
[ -f "$P8" ] || die "notary key not found at: $P8"

echo "Repository:       $REPO"
echo "Signing identity: $IDENTITY"
echo "Notary key:       $P8  (key id $KEY_ID)"
echo ""

# A notary key that does not work fails the release at its very last step, after a full build and
# a signing round. One API call now finds that out first.
echo "Checking the notary credentials against Apple..."
xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null 2>&1 \
    || die "Apple rejected these notary credentials. The key may be revoked, or lack the role
       notarisation needs. Create a new App Store Connect key (Users and Access, Integrations)
       and update $ASC_JSON."
echo "  Apple accepts them."
echo ""

# The .p12

P12_PW="$(uuidgen)"
P12="${1:-}"

if [ -n "$P12" ]; then
    [ -f "$P12" ] || die ".p12 not found: $P12"
    printf "Enter the password for %s: " "$(basename "$P12")"
    read -rs P12_PW; echo ""
    [ -n "$P12_PW" ] || die "empty password"
else
    P12="$WORK/developer-id.p12"
    echo "Exporting the signing certificate from your keychain."
    echo "macOS will ask you to allow this - click Allow."
    echo ""
    # `security export` cannot select one identity, so this exports every identity in the keychain
    # and narrows it below. Without the narrowing the App Store distribution key would go to CI as
    # well, and this release has no use for it.
    security export -k "$HOME/Library/Keychains/login.keychain-db" \
        -t identities -f pkcs12 -P "$P12_PW" -o "$WORK/all.p12" \
        || die "the keychain export failed or was denied."

    if command -v openssl >/dev/null 2>&1 && \
       openssl pkcs12 -in "$WORK/all.p12" -passin "pass:$P12_PW" -nodes \
            -legacy -out "$WORK/all.pem" 2>/dev/null; then
        # Rebuild a .p12 holding only the Developer ID Application identity.
        python3 - "$WORK/all.pem" "$WORK/one.pem" "$IDENTITY" <<'PY'
import re, sys
src, dst, want = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
# Each bag is a friendlyName/subject header followed by one PEM block.
blocks = re.findall(r'(?:^.*?\n)*?-----BEGIN [^-]+-----.*?-----END [^-]+-----\n',
                    text, re.S | re.M)
keep = [b for b in blocks if want in b or 'PRIVATE KEY' in b]
cert = [b for b in blocks if want in b and 'CERTIFICATE' in b]
if not cert:
    sys.exit(1)
open(dst, 'w').write(''.join(keep))
PY
        if [ -s "$WORK/one.pem" ] && openssl pkcs12 -export -in "$WORK/one.pem" \
                -passout "pass:$P12_PW" -out "$P12" 2>/dev/null; then
            echo "  Narrowed the export to the Developer ID certificate alone."
        else
            cp "$WORK/all.p12" "$P12"
        fi
    else
        cp "$WORK/all.p12" "$P12"
    fi
fi

# Import the .p12 exactly as the workflow will, into a throwaway keychain. Unlike OpenSSL,
# `security import` reads Keychain's legacy-encrypted .p12 without complaint, so this is the test
# that matches what the runner does.
VERIFY_KC="$WORK/verify.keychain-db"
security create-keychain -p "$(uuidgen)" "$VERIFY_KC" >/dev/null
security import "$P12" -k "$VERIFY_KC" -P "$P12_PW" -T /usr/bin/codesign >/dev/null 2>&1 \
    || die "the .p12 could not be imported. If you supplied it, check the password."
FOUND="$(security find-identity -v -p codesigning "$VERIFY_KC" 2>/dev/null)"
echo "$FOUND" | grep -q "Developer ID Application" \
    || die "that .p12 holds no Developer ID Application certificate:
$FOUND"
echo ""
echo "Certificates in the .p12:"
printf '%s\n' "$FOUND" | grep -oE '"[^"]+"' | sed 's/^/  /'
echo ""

# Upload

echo "Setting secrets on ${REPO}..."
base64 < "$P12" | gh secret set MACOS_CERTIFICATE_P12 --repo "$REPO"
printf '%s' "$P12_PW" | gh secret set MACOS_CERTIFICATE_PASSWORD --repo "$REPO"
base64 < "$P8" | gh secret set NOTARY_KEY_P8 --repo "$REPO"
gh secret set NOTARY_KEY_ID --repo "$REPO" --body "$KEY_ID"
gh secret set NOTARY_ISSUER_ID --repo "$REPO" --body "$ISSUER"
unset P12_PW

echo ""
gh secret list --repo "$REPO"
echo ""
echo "Done. The next v* tag builds, signs, notarises and attaches the Mac disk image by itself."
