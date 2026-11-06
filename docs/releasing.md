# Releasing Library Merger

This follows [meh.md's release flow](https://github.com/AndreasSko/meh.md/blob/444696e4257cc848469b345d80689d557c7d93e9/docs/releasing.md),
adapted to one iOS app and the `master` branch.

1. Merge to `master`: **Internal TestFlight** signs, uploads, waits for Apple
   processing, and assigns the build to the internal group. Documentation-only
   merges do not build. PRs only compile Release without signing or secrets.
2. Run **Beta** (`gh workflow run beta.yml`, optionally `-f commit=<sha>`).
   It promotes the existing build to the public TestFlight group, with the
   draft release text as What to Test. Apple may require Beta App Review.
   The draft is pointed at the promoted commit.
3. Edit and publish the draft GitHub release. **App Store release** finds
   that commit's tested build, checks the version matches the tag, sets
   What's New, attaches the build, and validates the App Store version.
4. Edit review notes and submit for review in App Store Connect. New
   versions default to release after approval (`AFTER_APPROVAL`); an
   existing version keeps its manually chosen release setting.

Beta and App Store promotion never rebuild the app. Successful internal
uploads record `testflight/IOS` on their commit as `version (build)`.
Promotion searches back up to 50 first-parent commits for that status and
refuses to reuse a build if app files changed afterward.

## Versions and notes

`scripts/app_version.sh` uses one minor version above the highest `vX.Y.Z`
release tag in the commit's history, with the project's `MARKETING_VERSION`
as a minimum. A tag on the commit itself is excluded: that commit was
built before it was tagged. Without release tags, the project value is used.
The initial project minimum is `0.11.0`, advancing past the previously
prepared `0.10.1` even though this repository has no release tags yet.
No bootstrap tag or published historical release is required. Once
`v0.11.0` is published, later commits build `0.12.0`.

This replaces manual patch bumps: every release advances the minor version,
including bug-fix releases. Local builds retain the project value. Build
numbers come from App Store Connect; CI does not edit the project or
commit version bumps.

**Release notes** adds each merged PR's first prose paragraph to the draft
for the current version. Label infrastructure PRs `no-release-note` to skip
this. Run it manually with `pr=<number>` to add a missed PR. Edit the draft
before release: later merges may describe changes absent from an earlier
promoted beta. Move those entries into the next version's draft instead.
Markdown becomes plain text and PR references are removed for Apple.

The existing App Store listing remains managed in App Store Connect.
Only What's New in `APP_STORE_LOCALE` (default `en-US`) changes. An editable
version is reused to preserve its screenshots and review details; otherwise
Apple creates a new version. Complete any missing metadata or screenshots
in App Store Connect if validation reports them. Before final submission,
edit German and any other localized What's New text there; this workflow
does not translate the release notes.

Sentry symbol upload also remains manual. After an internal build, download
the `ios-dSYMs-<commit>-<build>` artifact from its Actions run, unzip it,
and upload the dSYMs to Sentry
with `sentry-cli debug-files upload`. Apple's symbol upload during export
does not deliver symbols to Sentry. Do this before using its crash reports
for diagnosis.

## Setup after merging

Create GitHub environments `testflight` and `app-store`. Restrict
`testflight` to `master`; allow `master` and `v*` tags in `app-store`.
Add the following values yourself; no credentials are stored in the repo.

| Name | Kind | Environment |
| --- | --- | --- |
| `ASC_APP_ID` | Variable, Library Merger's numeric app ID | Both |
| `ASC_KEY_ID` | Secret, API key ID | Both |
| `ASC_ISSUER_ID` | Secret, issuer ID | Both |
| `ASC_PRIVATE_KEY` | Secret, entire `.p8` contents | Both |
| `APPLE_TEAM_ID` | Variable, signing team ID | `testflight` |
| `TESTFLIGHT_INTERNAL_GROUP_ID` | Variable, internal group ID | `testflight` |
| `SIGNING_CERTIFICATES_P12_BASE64` | Secret, base64 Apple Distribution `.p12` | `testflight` |
| `SIGNING_CERTIFICATES_PASSWORD` | Secret, `.p12` password | `testflight` |
| `IOS_PROFILE_BASE64` | Secret, base64 App Store distribution profile for `de.andreas-sk.jwlm` | `testflight` |
| `TESTFLIGHT_BETA_GROUP_ID` | Variable, public beta group ID | `app-store` |
| `APP_STORE_LOCALE` | Optional variable, exact existing locale | `app-store` |

Use a Developer API key for internal delivery and an App Manager key for
beta and App Store preparation, with access to this app. The profile and
certificate must belong to `APPLE_TEAM_ID`. Export settings use the
installed profile's UUID, so no profile naming convention is required.
The IPA is eligible for external TestFlight and the App Store.

Nothing is uploaded from this PR. After setup, run **Internal TestFlight**
on `master` for the first signed delivery. Until credentials are added,
its publishing job will fail; PR validation needs none of them.

## Recovery

Rerun a failed workflow after fixing the cause. To retry preparation, run
**App Store release** with `tag=vX.Y.Z`. Versions already in review or
released are left alone. Submission stays manual.

If Apple rejects a binary, make the release a draft and delete its tag
before merging the fix so the version can be reused. Point the draft at
`master`, wait for the corrected internal build, promote it, and republish.
Move notes from any next-version draft created while the tag existed.
