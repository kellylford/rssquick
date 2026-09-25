#!/bin/bash
# build.sh [debug|release|test|dist|clean] - debug is the default.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-debug}" in
    test)    swift test --package-path "$here" ;;
    clean)   rm -rf "$here/.build" "$here/artifacts" ;;
    release) "$here/build/make-app.sh" release ;;
    # The signed, notarized disk image. Needs a Developer ID certificate and notarization
    # credentials; see the signing section of README.md.
    dist)    shift; "$here/build/release.sh" "$@" ;;
    debug)   UNIVERSAL=0 "$here/build/make-app.sh" debug ;;
    *)       echo "usage: build.sh [debug|release|test|dist|clean]" >&2; exit 2 ;;
esac
