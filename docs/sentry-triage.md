# Sentry triage, 12 October 2026

Read-only snapshot of `andreas-skorczyk/library-merger`, compared with
production 0.8.1 (5), iOS playlist PR #101, and Go playlist PR #189.
The six unresolved groups contain 707 lifetime events. Only 30 detailed
events were available to this account, from 12 September to 11 October;
29 are 0.8.1 (5), one is 0.8.0 (3), all use Sentry Cocoa 8.58.0.
These are event counts, not unique crashes or current affected users.
The retained events record 23 users across groups, with overlap possible.
Pagination was exhausted, including explicit 90-day and historical queries.
The account's retention configuration was not independently established.
No production errors, status, grouping, or settings were changed.

## Families and priority

| Family | Sentry groups | Lifetime / retained | Evidence and priority |
| --- | --- | --- | --- |
| Opaque import failures | [2](https://andreas-skorczyk.sentry.io/issues/6663754597/) | 644 / 14 | All retained events are imports of existing readable files. The app replaced NSError userInfo, losing the Go reason. Highest observability priority; actual underlying causes cannot be reconstructed. |
| File acquisition timeout | [7Q](https://andreas-skorczyk.sentry.io/issues/7714408168/) | 5 / 2 | Files did not exist or were unreadable after 60–61 seconds. Acquisition used fileExists, ignored the coordinated accessor URL, and blocked while polling. High priority. |
| SIGPIPE with Go | [7M](https://andreas-skorczyk.sentry.io/issues/7620991002/), [5A](https://andreas-skorczyk.sentry.io/issues/7486209799/) | 39 / 7 | Same signal across versions, with Go write, HTTP/2, or TLS cleanup frames. Main-thread UIKit frames are not proof that UIKit caused termination. Address signal-monitor ownership; do not call all 39 actual process exits. |
| Picker wait on Mac | [7N](https://andreas-skorczyk.sentry.io/issues/7626791280/) | 17 / 5 | Every retained event runs the iOS app on Mac, with document picker → NSSavePanel → nested semaphore/run loop. No Go merge activity is established. Instrument UI boundaries and runtime; investigate on Mac separately. |
| Native iOS share-sheet wait | [7S](https://andreas-skorczyk.sentry.io/issues/7729865921/) | 2 / 2 | Share-sheet construction waits on synchronous XPC in SFShareSheetSlotManager. Different execution environment and stack from picker waits. Instrument and retain hang detection; no demonstrated app-code fix. |

## Changes in the Sentry workstream

- Preserve NSError domain, code, userInfo, description, and underlying error
  when adding diagnostics. Promote the original description to the SDK's
  debug-description field so the exception value includes the Go reason.
- Scope errors by operation, stage, merge side, and known failure family,
  retaining Sentry default cause grouping. Unknown causes still carry their
  original descriptions; classification is diagnostic, not a root-cause proof.
- Record provider/acquisition timing and completion/failure/cancellation
  boundaries. Custom context and breadcrumbs omit backup URLs and filenames.
  Original platform NSError metadata is preserved and can contain file paths.
  Unrecognized providers are tagged unknown rather than assumed local.
- Coordinate and snapshot every selected file off the main thread, resolving
  symbolic links and using the accessor's actual URL so snapshots contain
  independent bytes. Refresh iCloud download status and asynchronously poll
  until the current version is available, with cancellation and a 60-second
  readiness timeout. A downloaded but stale copy is not treated as ready.
  Private snapshots live through the Go import and are removed after
  completion or cancellation.
  Third-party coordination can take longer; the iCloud timeout does not bound
  synchronous provider work. It no longer blocks the main thread.
- Close Sentry before preference reconfiguration, then make Go's ignored
  SIGPIPE disposition explicit as SIG_IGN before installing Sentry. Other
  crash signals and hang detection remain enabled. Add execution_environment
  (`ios_device`, `ios_on_mac`, `mac_catalyst`, `simulator`). Reporting stays
  opt-in; debug XCTest/UI tests cannot enable production reporting.
- Add picker and share-sheet boundary breadcrumbs, share completion/error
  timing, conflict-resolution error capture, and catalog-download error capture.
  Expected cancellations and normal merge conflicts are not reported as bugs.

## SIGPIPE rationale and evidence limits

Go's Apple signal forwarding deliberately ignores SIGPIPE because the signal
can arrive on a thread other than the writer. Sentry's signal monitor preserves
literal SIG_IGN, but Go represents its behavior using a function handler.
That distinction permits Sentry to record a fatal event for a signal that Go
would ignore. The retained stacks are consistent with this explanation; they
do not establish whether any particular user's process actually exited.

Sources inspected:

- [Go 1.25.5 Apple SIGPIPE forwarding](https://github.com/golang/go/blob/go1.25.5/src/runtime/signal_unix.go#L1115-L1119)
  matches the compiler version embedded in the production framework.
- [Apple iCloud download states](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus)
  distinguish a stale downloaded copy from the current version.
- [Sentry Cocoa 8.58 signal monitor](https://github.com/getsentry/sentry-cocoa/blob/8.58.0/Sources/SentryCrash/Recording/Monitors/SentryCrashMonitor_Signal.c)
  preserves an existing ignored disposition, captures otherwise, and restores
  handlers before raising the signal again.

Regression tests exercise actual SDK crash-monitor installation with a
localhost-only DSN and discarded events: SIGABRT acquires a monitor while
SIGPIPE remains ignored and can be raised without terminating the process.
Event-builder tests likewise intercept and discard events, checking original
Go descriptions, underlying causes, scoped grouping, and cancellation.
No verification sends events to the production Sentry endpoint.

## Separate source-review workstream

These defects were found by source inspection; the lost Go descriptions do
not establish them as causes of the 644-event import group:

- Fatal hash-read failure, ignored manifest/ZIP read-close failures, and partial
  export replacement.
- Unbounded, negative, or overflowing ID-indexed allocations and malformed
  UserMark location references.
- Broad Inbox/export cleanup, nullable statistics/share state, and export-name
  collisions or invalid document-directory assumptions in the iOS layer.

They ship separately on top of the playlist work. The Go API/model JSON stay
unchanged, but the checked-in iOS framework must still be rebuilt from the
exact hardened Go commit. Physical-device JW Library restore, real provider
latency, and iOS-on-Mac picker hangs require separate live verification.
