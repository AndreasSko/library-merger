# Playlist support validation

This feature adds playlist merging to Library Merger and the shared Go/CLI
implementation. The reusable tests cover ordering, intentional repeats,
custom media, playback settings, conflict choices and safe rejection of
unsupported inputs.

## What each test layer proves

| Layer | Responsibility |
| --- | --- |
| Go model/merger | Occurrence matching, ordering, media identity/path collisions, deep copies and invalid relationships |
| Gomobile | Import/merge/export, all eight changed settings with both choices, serialized conflict context and retry/remerge behavior |
| CLI | Combined playlist changes and repeats, automatic thumbnails, unattended choices, interactive choices, cancellation and EOF |
| Swift controller/presentation | Shared-framework integration, session/reset guards, visible changed fields, source context and exact timing labels |
| iPhone/iPad UI | Actual choice, cancellation, retry, sharing and largest-text reachability |
| Archive validators | Complete ordered semantics, media bytes, SQLite integrity/foreign keys and the manifest database hash |

The shared scenario table covers individual ordering and playlist-union cases
through Gomobile. CLI archive cases retain combined changes and repeats rather
than repeating that whole matrix. Mobile JSON-contract assertions share the
eight-setting table; cosmetic merges run once per path/direction because there
is no conflict choice. A generic screenshot-only XCTest was removed in favor
of the targeted presentation test with field/context assertions.

## Repeatable evidence

The mandatory fictional archive matrix contains 37 contracts and 71 directed
runs. All 20 embedded archives regenerate byte-for-byte. XCTest produces 16
mandatory exports; optional original archives add eight local exports. Original
backups are never required for hosted CI.

See [test commands](../scripts/README-playlists.md) and the current
[Go PR checks](https://github.com/AndreasSko/go-library-merger/pull/189/checks)
and [iOS PR checks](https://github.com/AndreasSko/library-merger/pull/101/checks).
The iOS Build workflow retains detailed reports and XCTest results in its
`playlist-build-and-contracts` artifact. Raw historical reports are local
release evidence rather than source files; scripts regenerate the reports.

Actual app screenshots use fictional playlists and media with verified
publication metadata: [publication](playlist-refinement-evidence/publication-action-choice-native.png),
[file](playlist-refinement-evidence/binary-settings-conflict.png),
[largest-text context](playlist-refinement-evidence/publication-largest-text-context.png)
and [largest-text choice](playlist-refinement-evidence/publication-largest-text-choice.png).

## Framework and release boundary

The embedded framework was built from clean Go commit
`df219073073090aee2695cdc2ef4b3f2a69a2003`; `Gomobile.source.json`
records the source fingerprint and all 15 framework-file hashes. Subsequent
review cleanup changes tests and documentation only. Production Go/Swift source,
embedded fixtures and framework bytes are unchanged.

The signed local candidate is Library Merger 0.9.0 (6), minimum iOS 15.
Merge/release Go before the dependent iOS integration. App Store Connect
credentials and an available build number are required before upload.

Automated and simulator evidence supports a small TestFlight cohort. Earlier
macOS JW Library acceptance verified ordering, custom photo/video playback and
restart persistence, but predates the final cosmetic/UI refinement. Physical
iPhone/iPad restore, publication playback, sharing, persistence and successful
fresh native backup re-export remain required for broad App Store rollout.
See [the rollout plan](playlist-rollout.md). Nothing has been uploaded.
