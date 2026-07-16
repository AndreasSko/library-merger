# Agent context for Library Merger

## Gomobile dependency

`Gomobile.xcframework` is generated from the sibling `go-jwlm` repository and
is checked in. It does not update automatically. After exported Gomobile API or
model JSON changes, update the Swift callers or decoders and rebuild from the
Go repository root:

```
gomobile bind -target=ios -o ../ios-jwlm/Gomobile.xcframework ./gomobile
```

Record the source Go commit in the iOS PR. Merge or release the Go change before
the dependent iOS change.

## Verification

Build with the `LibraryMerger` scheme for an iOS Simulator destination. For
changes affecting backup compatibility, also import original and modified
backups, merge and export them, then inspect the exported SQLite data and verify
the database SHA-256 digest matches `userDataBackup.hash` in `manifest.json`.

When modifying a `.jwlibrary` fixture, recalculate that manifest hash before
repacking it. Simulator fixture injection may use an open-in-place-enabled test
build, but do not commit that setting to the production `Info.plist`.
