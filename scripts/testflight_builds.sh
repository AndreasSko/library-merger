#!/bin/bash
# Find the newest verified iOS build at or before a commit. Documentation
# changes may reuse a build; app changes must have their own upload status.
set -euo pipefail
rev=${1:?usage: $0 <rev>}
target=$(git rev-parse "$rev^{commit}")
# Keep in sync with paths-ignore in testflight.yml.
not_app=(':(exclude)docs' ':(exclude,glob)**/*.md')
for sha in $(git rev-list --first-parent --max-count=50 "$target"); do
  ios=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/status" \
    --jq '[.statuses[] | select(.context == "testflight/IOS")][0]
      | select(.state == "success") | .description // empty')
  [[ -n $ios ]] || continue
  if ! git diff --quiet "$sha" "$target" -- . "${not_app[@]}"; then
    echo "The app changed after ${sha:0:7}, the newest commit with a build." >&2
    echo "Wait for Internal TestFlight on ${target:0:7}, or rerun it." >&2
    exit 1
  fi
  if [[ $ios =~ ^([0-9]+\.[0-9]+\.[0-9]+)\ \(([0-9]+)\)$ ]]; then
    printf 'commit=%s\nversion=%s\nios=%s\n' \
      "$sha" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    exit 0
  fi
  echo "Invalid TestFlight status on $sha: $ios" >&2
  exit 1
done
echo "No commit with a TestFlight build near ${target:0:7}." >&2
exit 1
