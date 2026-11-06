#!/bin/bash
# Prints the app version that a build of the current commit gets.
#
# It is one minor version above the newest release tag (v1.2.3) in the
# commit's history, or MARKETING_VERSION from the project when that is
# higher. Raise the project value only to jump ahead, say to 1.0.0.
# A tag on the commit itself doesn't count: that commit was built before
# the release named it. See docs/releasing.md.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
semver='^[0-9]+\.[0-9]+\.[0-9]+$'

floor=$(sed -nE 's/.*MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+);.*/\1/p' \
  LibraryMerger.xcodeproj/project.pbxproj | sort -uV | tail -1)
[[ $floor =~ $semver ]] || {
  echo "No MARKETING_VERSION in the project" >&2
  exit 1
}

released=$(git tag --list 'v*' --merged HEAD --no-contains HEAD |
  sed -n 's/^v//p' | grep -E "$semver" | sort -V | tail -1 || true)
next=$floor
if [[ -n $released ]]; then
  IFS=. read -r major minor _ <<< "$released"
  next=$(printf '%s\n' "$floor" "$major.$((minor + 1)).0" | sort -V | tail -1)
fi
echo "$next"
