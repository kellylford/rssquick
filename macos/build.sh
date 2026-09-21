#!/bin/bash
# build.sh [debug|release|test|clean] - debug is the default.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-debug}" in
    test)    swift test --package-path "$here" ;;
    clean)   rm -rf "$here/.build" "$here/artifacts" ;;
    release) "$here/build/make-app.sh" release ;;
    debug)   UNIVERSAL=0 "$here/build/make-app.sh" debug ;;
    *)       echo "usage: build.sh [debug|release|test|clean]" >&2; exit 2 ;;
esac
