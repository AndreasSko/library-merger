# iOS playlist support

Playlists with the same name are combined additively. Ordered occurrences,
custom media, thumbnails, trims, durations, accuracy, and end actions are
preserved; conflicting settings require a left/right choice. The comparison
shows only the settings that differ, with a specific question and enough
playlist and source context to identify the item. Thumbnail differences resolve
automatically using the shared Go policy: prefer a present thumbnail, then a
stable content identity and filename tie-breaker. Renamed playlists remain separate and
deletions do not propagate between backups.

Publication conflicts use the imported title, with the item label as a fallback.
Go supplies an optional official link when the source identity is reliable.
English/German document identities and undated video key/track identities are
supported; other languages or ambiguous media identities omit the link.
Swift validates and formats this metadata without comparing or merging backups.
The offline broadcasting fixtures retain verified source metadata and fictional
image bytes, so routine regression tests require no download or computer use.

Unsupported marker/verse/paragraph clips, multiple mappings per item,
contradictory order, ambiguous edits beside repeated insertions, malformed
relationships, and missing or corrupt media stop the operation. The iOS app
never silently omits playlists. Its support screen explains these limits.

## Framework provenance and merge dependency

`Gomobile.source.json` inventories every checked-in framework file and pins Go
commit `df219073073090aee2695cdc2ef4b3f2a69a2003` from
[Go PR #189](https://github.com/AndreasSko/go-library-merger/pull/189).
The framework was rebuilt from a clean checkout using the exact x/mobile
version in that commit. Device and simulator slices are generated together.

Merge/release Go PR #189 before merging or releasing this iOS integration.
A squash merge may assign a different Git commit to equivalent source; the
recorded source fingerprint and immutable PR commit retain build provenance.

For the source check, use a clean Go checkout at the recorded framework
commit. Later test-only commits intentionally have a different full source
fingerprint. Verify locally with:

```sh
python3 scripts/verify-gomobile-provenance.py --go-source ../go-jwlm
```

Rebuild after changing the exported Go API or JSON contract:

```sh
gomobile bind -target=ios -o ../ios-jwlm/Gomobile.xcframework ./gomobile
```

Install both gomobile and gobind at the module-pinned version first, commit the
Go source, rebuild from its clean checkout, and regenerate the provenance.

## Session and media lifetime

Input media stays available for conflict cancellation, retry, and repeated
exports. Replacement or New merge closes old inputs.
Operations are serialized. Session identities reject abandoned picker,
import, merge, resolution, and export callbacks after reset. Cancel discards
partial conflict decisions; export requires a completed full merge.

## Verification and rollout

The mandatory suite uses deterministic fictional archives and media. Optional
original JW Library archives extend it locally without being committed. See
[test instructions](../scripts/README-playlists.md) and
[the rollout checklist](playlist-rollout.md). The
[current validation summary](playlist-candidate-validation.md) separates
automated coverage from the native acceptance required for rollout.

This candidate raises the minimum supported OS to iOS 15 as approved for the
current Xcode toolchain. Marketing version is 0.9.0 and candidate build is 6.
Check App Store Connect for an unused build number before upload.
