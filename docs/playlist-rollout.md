# Playlist rollout

## Merge and TestFlight

1. Require green final-head checks on Go PR #189 and the dependent iOS PR.
   Merge/release Go first. Check framework provenance and both slices.
2. Use the signed 0.9.0 candidate only after controller/UI tests and exported
   archive audits pass. Authenticate App Store Connect and verify that build
   number 6 is unused; increase it and rebuild if necessary.
3. Upload without broad automatic distribution. Start with a small TestFlight
   cohort using copies of backups they can restore safely. Keep their original
   backups. Include the supported scope below in What to Test.

## What to Test

Merge same-name and separate playlists with custom photos/videos, front/middle
insertions, repeated media, thumbnail changes, trims, end actions, and duration
conflicts. Thumbnail-only differences should complete without a choice; other
conflicts should show only changed settings, with an identifiable item and
publication title. Check the optional official source link. Try both input
directions. Cancel and retry conflicts, start New
merge, export twice, and share/save the archive from iPhone and iPad.

Restore the exported archive into a disposable JW Library installation. Check
order, every repeated occurrence, thumbnails, custom photo/video playback,
and publication playback. Restart JW Library and export a fresh native backup.
Validate ZIP CRC, SQLite integrity/foreign keys, the database manifest SHA-256,
complete ordered playlist metadata, and media payload bytes after reimport.
Record exact Library Merger build, device/OS, and JW Library version.

## Public App Store gate

Complete native restore, playback, persistence, and successful native re-export
on physical iPhone and iPad before rollout to the full user base. The desktop
JW Library app's backup share flow crashed even before any merged restore; a
recovered temporary archive with a stale manifest hash is incomplete acceptance.
Controller and simulator evidence cannot establish physical-device sharing or
successful native re-export.

Investigate any missing/extra/reordered occurrence, wrong resolved setting,
missing media, unexplained conflict, import error, or crash before broadening.
Use phased release after beta acceptance and retain the previous release for
regression comparison. Save each new minimal fictional reproduction in the
portable suite so the next run can be automated.

## Supported scope

Merging is additive; it does not infer deletions or renamed playlist identity.
Marker/verse/paragraph clips, multiple mappings per item, contradictory order,
and ambiguous repeated edits are rejected explicitly. The iOS app preserves
the loaded backup and produces no export that silently omits these playlists.
Explain this scope in beta notes and release notes.
