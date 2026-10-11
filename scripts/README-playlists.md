# Playlist integration tests

`LibraryMergerTests/Fixtures` contains small synthetic archives with embedded
synthetic media. They exercise large tick values, insertions, setting and
duration conflicts, unsupported multiple-location mappings, and empty input.
Rebuild them with `python3 scripts/build-playlist-test-fixtures.py`; this reads
the sibling Go repository's empty schema template and updates manifest hashes.

Original archives are optional and deliberately not checked in. For local
validation, copy the four `scenario-*` directories into
`LibraryMergerTests/Fixtures/Original/`. The original-archive test reports a skip
when they are absent. They are resources of the test bundle only.

Run `xcodebuild test` with project `LibraryMerger.xcodeproj`, scheme
`LibraryMerger`, an available iOS Simulator destination, and
`-only-testing:LibraryMergerTests -only-testing:LibraryMergerUITests
-parallel-testing-enabled NO`.

Tests export to the simulator app's `Documents/PlaylistValidation` directory.
Use `xcrun simctl get_app_container <device> de.andreas-sk.jwlm data` to locate
it while the simulator is booted, then run:

```sh
python3 scripts/verify-export-archives.py /path/to/Documents/PlaylistValidation
python3 scripts/verify-playlist-exports.py /path/to/Documents/PlaylistValidation
```

Run this before reinstalling the test app, which can replace its container.
For optional original scenarios, append
`--originals LibraryMergerTests/Fixtures/Original` to the specific verifier;
that run requires their eight exports in addition to the portable outputs.
The verifiers check selected settings, ordering, SQLite integrity, foreign keys, media bytes,
and the manifest hash for every output. Targeted presentation tests retain
binary and publication screenshots as XCTest attachments.
The production Info.plist is unchanged.

## Extended external fixture audit

Audit an entire external collection recursively, including archives that are
not named by a happy-path scenario:

```sh
python3 scripts/validate-playlist-fixtures.py /path/to/jw-playlist-merge-fixtures \
  --report /tmp/playlist-fixture-audit.json
```

This verifies archive and manifest hashes, SQLite integrity and foreign keys,
contiguous playlist order, media and thumbnail payloads, empty named playlists,
and all three marker tables. Its semantic snapshot excludes database IDs and
archive paths, while retaining every ordered occurrence. Duplicate labels or
repeated uses of the same media therefore remain distinct entries with their
own trims, end action, duration, thumbnail, and marker data. Every archive must
be listed in `fixture-index.json`; `--allow-unindexed` is available only for
diagnosing a collection while its index is being rebuilt.

Exercise the public Go/Gomobile merge contract without the iOS UI from the
sibling Go repository:

```sh
GOCACHE=/tmp/go-build-playlist-probe go build -o /tmp/probe-playlist-merge \
  ../ios-jwlm/scripts/probe-playlist-merge.go
/tmp/probe-playlist-merge LEFT RIGHT detect OUTPUT
```

`detect` emits JSON with either `success` or the typed playlist conflicts. It
does not export when conflicts exist. Its `initialConflicts` records the first
unresolved phase, whose export gate is checked before any simulated resolution.
Its `conflicts` aggregates both serialized sides from subsequent phases reached
by simulated left choices, so later duration dimensions remain observable.
Use `left` or `right` to resolve every
playlist conflict to that side and export a result for the Python semantic
audit. The probe creates all merger scratch data in an isolated temporary
directory. Marker-bearing archives are expected to fail during import with the
explicit unsupported-table error until the Go importer supports those rows.

Run all indexed scenario contracts and retain the detailed evidence:

```sh
python3 scripts/execute-playlist-fixture-scenarios.py \
  /path/to/jw-playlist-merge-fixtures \
  --probe /tmp/probe-playlist-merge \
  --report /tmp/playlist-fixture-execution-report.json
```

This compares declared reference archives by complete semantic content,
verifies self and repeated merges against their input, checks the additive
occurrence multiset and media-byte union, and enforces order constraints.
Conflict resolutions include accuracy, trims, actions, custom duration, and
location base duration.


## Mandatory portable contracts

CI regenerates and byte-compares all checked-in synthetic archives, verifies
`Gomobile.source.json` against every framework file and a clean immutable Go
source checkout, and runs Simulator tests against that embedded binary.
The fingerprint uses tracked source and schema files. Ignored diagnostics are
excluded; extra Go files in active package directories or vendor are rejected.
External original archives remain optional. Their absence does not remove the
portable repeated-occurrence, thumbnail, conflict-session, or export checks.

The separate generated portable matrix contains 37 contracts and 71 fictional
archives, including seeded repeated-media insertions. Run it without external
data:

```sh
(cd ../go-jwlm && GOCACHE=/tmp/go-build-playlist-probe go build -o /tmp/probe-playlist-merge ../ios-jwlm/scripts/probe-playlist-merge.go)
python3 scripts/build-portable-playlist-matrix.py /tmp/portable-playlists --go-source ../go-jwlm
python3 scripts/validate-playlist-fixtures.py /tmp/portable-playlists --report /tmp/portable-structure.json
python3 scripts/test-playlist-contract-harness.py
python3 scripts/execute-playlist-fixture-scenarios.py /tmp/portable-playlists --probe /tmp/probe-playlist-merge --report /tmp/portable-execution.json
```

Every two-input contract runs in both directions. Successful output is remerged
with its input and compared semantically; declared input-order independence is
checked explicitly. Duplicate-label order uses occurrence settings. Unknown
invariants fail validation. Reports fingerprint the index, probe, oracle and
validator; successful statuses with failing process exit codes are rejected.
Declared conflict dimensions must match the changed fields in the serialized
models under each unique conflict Key. Unsupported/rejection contracts must
match their declared nonempty `errorSubstring`. Probe execution is limited to
60 seconds per invocation; verifier regression subprocesses to 30 seconds.
Unordered sibling insertions may use either valid order unless a contract
requires one exact order.

For any Simulator export directory, the generic verifier checks supported
manifest/schema versions, the database SHA-256 digest, SQLite integrity and
foreign keys, playlist order, media hashes and thumbnail payloads:

```sh
python3 scripts/verify-export-archives.py /path/to/Documents/PlaylistValidation --report /tmp/exports.json
python3 scripts/verify-playlist-exports.py /path/to/Documents/PlaylistValidation
```

Go CI also runs the complete uncached suite with the race detector and
cross-package coverage. Marker, Bible-verse-map and paragraph-map rejection
branches have separate portable Go regressions, including explicit playlist
omission and export/readback. Invalid relationships and missing, corrupt or
hostile-path media have mandatory negative regressions.


The iOS CI invocation selects both `LibraryMergerTests` and
`LibraryMergerUITests` with parallel testing disabled. It uses the stable
`macos-26` runner and explicitly verifies Xcode 26.6. The checked-in framework
contains static C/Objective-C archives, with no Swift module; its producer
Xcode version remains recorded independently in `Gomobile.source.json`.
CI verifies all framework hashes, then compiles, links and tests that exact
binary with the consumer toolchain. A successful job establishes compatibility
with that consumer. Missing Xcode support fails before Simulator testing.
CI retains both toolchains, SDK versions, simulator identities and results.

The same hosted job runs `LibraryMergerUITests` sequentially on an available
iPad and retains a separate `PlaylistIPadUITests.xcresult` bundle. If the image
has no predefined iPad, CI creates a task-owned iPad from a device type
supported by an available iOS runtime and removes it after testing. The full
unit/UI run and export audits remain on iPhone; the iPad run covers tablet
sharing and cancellation.

The specific export verifier requires all 16 portable outputs. A nonempty
subset, a misspelled output name or a missing repeated-occurrence/thumbnail/
session regression export fails. When `--originals` is supplied, all eight
original scenario outputs (both input directions) are required in addition to
the 16 portable outputs; they cannot substitute for portable coverage. Without
that option, original scenario outputs are not part of the accepted inventory.
The generic archive verifier remains usable for arbitrary export directories.

Both synthetic generators normalize the trigger-managed `LastModified` row to
`2020-01-01T00:00:00Z` after all mutations, then compute the database hash and
pack fixed-timestamp ZIP entries. The embedded `mixed-hashes` fixture and its
portable self-merge contract use two identical media occurrences backed by
separate canonical/native hash rows within one archive. The validator projects
payload identity as a set of actual byte digests, so safe media-row deduplication
cannot hide an occurrence loss or create a false inventory mismatch.

Synthetic archives also preserve the schema template's informational SQLite
writer-version header bytes and use `ZIP_STORED`; generated PNG data uses stored
DEFLATE blocks. The generators recheck SQLite integrity and foreign keys after
header normalization, then calculate the manifest's digest from those exact
final database bytes. This avoids runtime SQLite/zlib version drift in CI.


## Offline publication conflict example

Five reusable archives use the real publication identity and title
[JW Broadcasting—October 2026](https://www.jw.org/finder?wtlocale=E&lank=pub-jwb-142_1_VIDEO)
with a fictional playlist, label, trims, action and generated PNG pixels. The
[official metadata API](https://b.jw-cdn.org/apis/mediator/v1/media-items/E/pub-jwb-142_1_VIDEO)
verified `pub-jwb-142_E_1_VIDEO`, track 1, title, and duration 3434.64 seconds on
2026-10-12. No official video or image bytes are included, and regeneration,
source metadata assertions and screenshots require no web access or catalog.
`publication-source.json` retains this small verified metadata/link contract.

| Archive | Difference from `publication-base` |
| --- | --- |
| `publication-action` | End action changes from 0 to 3; all other settings stay equal |
| `publication-thumbnail-new` | Only thumbnail filename and pixels change |
| `publication-missing-title` | Location title is absent; preserve offline fallback |
| `publication-unknown-language` | Numeric language is absent; omit the source link rather than assume English |

Every archive points to symbol `jwb-142`, track 1, video media type 2,
location type 3, and base duration 34346400000 ticks. Base/action use English
MEPS language 0; the common trim is 25000000 ticks (2.5 seconds). The screenshot
scenario imports base/action and displays their conflict cards: only end action
belongs in the differing settings; title/source context remains visible, while
equal trim, duration and artwork do not become extra conflicts. Its resolved
export is named `publication-action`. Base/thumbnail-new should merge without
intervention and export as `publication-thumbnail`.

The verified source links use `finder?wtlocale=E&lank=pub-jwb-142_1_VIDEO` and,
for German, `wtlocale=X`. Both resolve to the exact localized video item.
`pub=jwb-142&track=1` redirects to the homepage and must not replace the verified
`lank` form. Website language metadata confirms E=English and X=German. The
numeric English mapping is corroborated by the Go catalog fixture; the numeric
German mapping is corroborated by the indexed original native archive. Tests
must omit a link for absent/unknown language or invalid publication identity.

Regenerate all 20 embedded archives, then run the offline publication checks:

```sh
python3 scripts/build-playlist-test-fixtures.py --go-source ../go-jwlm
python3 scripts/test-publication-fixtures.py
```

Publication screenshot/controller assertions live in `LibraryMergerTests`;
real test captures are retained in the XCTest result bundle. The metadata
contract does not require opening jw.org during XCTest.
