#!/bin/bash
# Prepare the tested binary; review notes and submission stay in ASC.
set -euo pipefail
: "${ASC_APP_ID:?}" "${VERSION:?}" "${IOS_BUILD:?}" "${RUNNER_TEMP:?}"
editable='PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY'
versions=$(asc versions list --app "$ASC_APP_ID" --platform IOS --paginate --output json)
version=$(jq -c --arg v "$VERSION" '[.data[] | select(.attributes.versionString == $v)][0] // empty' <<< "$versions")
if [[ -n $version ]]; then
  state=$(jq -r '.attributes.appStoreState' <<< "$version")
  if [[ " $editable " != *" $state "* ]]; then
    echo "::notice::iOS $VERSION is already $state, so it isn't changed."
    exit 0
  fi
else
  # Reuse an editable draft, including its screenshots and review details.
  version=$(jq -c '[.data[] | select(.attributes.appStoreState | IN(
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY"))][0] // empty' <<< "$versions")
  if [[ -n $version ]]; then
    asc versions update --version-id "$(jq -r .id <<< "$version")" \
      --version "$VERSION" --output table
  else
    asc versions create --app "$ASC_APP_ID" --version "$VERSION" \
      --platform IOS --release-type AFTER_APPROVAL --output table
  fi
fi
version_id=$(asc versions list --app "$ASC_APP_ID" --platform IOS --paginate --output json \
  | jq -er --arg v "$VERSION" '[.data[] | select(.attributes.versionString == $v)][0].id')
build_id=$(asc builds list --app "$ASC_APP_ID" --platform IOS \
  --version "$VERSION" --build-number "$IOS_BUILD" --output json | jq -er '.data[0].id')
asc localizations update --version "$version_id" --locale "${STORE_LOCALE:-en-US}" \
  --whats-new "$(cat "$RUNNER_TEMP/whats-new.txt")" --output table
asc versions attach-build --version-id "$version_id" --build-id "$build_id" --output table
asc validate --app "$ASC_APP_ID" --version-id "$version_id" --output table
printf 'iOS %s (%s) is prepared. Edit review notes and submit in [App Store Connect](https://appstoreconnect.apple.com/apps/%s).\n' \
  "$VERSION" "$IOS_BUILD" "$ASC_APP_ID" >> "$GITHUB_STEP_SUMMARY"
