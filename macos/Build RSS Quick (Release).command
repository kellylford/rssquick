#!/bin/bash
# Double-click this in Finder. Finder launches a .command file in Terminal, which is why these
# exist alongside the shell scripts: a .sh opens in an editor instead of running.
#
# Finder starts it in your home folder rather than beside itself, so the first thing it does is
# find its own directory.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

echo "Building a release app bundle…"
echo

"./build.sh" release
status=$?

echo
if [ $status -eq 0 ]; then
    echo "Done."
else
    echo "Failed with status $status. The output above says why."
fi

# The window stays open either way, so the output is still there to read - Terminal closes a
# .command window on its own otherwise, depending on its settings.
echo "Press Return to close this window."
read -r
exit $status
