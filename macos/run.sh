#!/bin/bash
# Build and run - the normal development loop, the same job run.cmd does on Windows.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One architecture: this is for trying a change, not for shipping.
UNIVERSAL=0 "$here/build/make-app.sh" "${1:-debug}"
open "$here/artifacts/RSS Quick.app"
