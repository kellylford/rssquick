#!/usr/bin/env bash
# Which platforms a release ships on, read from RELEASE-PLATFORMS at the repository root, which
# build/prepare-release.ps1 writes. A feature release (x.y.0) ships on all three; a fix (x.y.z)
# ships only where something changed, so iPhone testers are not sent a new build with nothing in
# it. The version counter is shared, so every number is one release: a Windows fix is 1.4.1, a
# later Mac fix 1.4.2, and the Mac never has a 1.4.1. WORKFLOW.md has the rule.
#
#   release-platforms.sh ships <windows|macos|ios>   prints true or false
#   release-platforms.sh notes <version>             prints the release notes' opening line, or
#                                                     nothing when the release is for all three
#
# A missing or empty file means all three, which is what every release before this file meant.
# An unknown word fails rather than quietly skipping a platform.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/RELEASE-PLATFORMS"
all=(windows macos ios)

platforms=()
if [ -s "$file" ]; then
  for word in $(tr -d '\r' < "$file"); do
    case "$word" in
      windows|macos|ios) platforms+=("$word") ;;
      *) echo "RELEASE-PLATFORMS: '$word' is not a platform (windows, macos, ios)" >&2; exit 2 ;;
    esac
  done
fi
[ ${#platforms[@]} -gt 0 ] || platforms=("${all[@]}")

has() { local p; for p in "${platforms[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }
name() { case "$1" in windows) echo Windows ;; macos) echo Mac ;; ios) echo "iPhone and iPad" ;; esac; }
join() { # "A", "A and B", "A, B and C"; "Mac, iPhone and iPad" rather than "Mac and iPhone and iPad"
  local n=$#; local out=""; local i=0
  for x in "$@"; do i=$((i+1))
    if [ $i -eq 1 ]; then out="$x"
    elif [ $i -eq $n ] && [[ "$x" != *" and "* ]]; then out="$out and $x"
    else out="$out, $x"; fi
  done; echo "$out"; }

case "${1:-}" in
  ships)
    [ -n "${2:-}" ] || { echo "usage: $0 ships <windows|macos|ios>" >&2; exit 2; }
    if has "$2"; then echo true; else echo false; fi ;;
  notes)
    [ -n "${2:-}" ] || { echo "usage: $0 notes <version>" >&2; exit 2; }
    shipped=(); unchanged=()
    for p in "${all[@]}"; do if has "$p"; then shipped+=("$(name "$p")"); else unchanged+=("$(name "$p")"); fi; done
    [ ${#unchanged[@]} -gt 0 ] || exit 0
    case "${shipped[*]}" in
      Windows|Mac) only="a ${shipped[0]}-only release" ;;
      *) only="a release for $(join "${shipped[@]}") only" ;;
    esac
    if [ ${#unchanged[@]} -eq 1 ]; then rest="version has"; else rest="versions have"; fi
    echo "**RSS Quick $2 is $only.** The $(join "${unchanged[@]}") $rest not changed, so there is nothing new to install there." ;;
  *) echo "usage: $0 ships <platform> | notes <version>" >&2; exit 2 ;;
esac
