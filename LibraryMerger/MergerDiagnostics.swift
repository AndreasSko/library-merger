import Foundation
import Sentry

enum MergerDiagnostics {
    struct Context {
        let operation: String
        let stage: String
        var side: MergeSide?
        var details: [String: Any] = [:]
    }

    static func diagnosticError(_ error: Error) -> NSError {
        let original = error as NSError
        var info = original.userInfo
        // NSError grouping otherwise shows only "go: Code 1". Preserve the
        // cause and underlying chain and give Cocoa's event builder a value.
        info[NSLocalizedDescriptionKey] = original.localizedDescription
        // Swift's bridged NSError can supply these lazily through accessors
        // without materializing them in its userInfo dictionary.
        if let reason = original.localizedFailureReason { info[NSLocalizedFailureReasonErrorKey] = reason }
        if let suggestion = original.localizedRecoverySuggestion {
            info[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        if let options = original.localizedRecoveryOptions { info[NSLocalizedRecoveryOptionsErrorKey] = options }
        if let anchor = original.helpAnchor { info[NSHelpAnchorErrorKey] = anchor }
        if info[NSDebugDescriptionErrorKey] == nil {
            info[NSDebugDescriptionErrorKey] = original.localizedDescription
        }
        return NSError(domain: original.domain, code: original.code, userInfo: info)
    }

    static func category(for error: Error) -> String {
        if case GeneralError.timeout = error { return "timeout" }
        let cause = error as NSError
        if cause.domain == NSCocoaErrorDomain { return "file_access" }
        if cause.domain == NSURLErrorDomain { return "network" }
        let message = error.localizedDescription.lowercased()
        if message.contains("backup incompatible") || message.contains("schema") { return "schema" }
        if message.contains("manifest") || message.contains("checksum") { return "manifest" }
        if message.contains("zip") || message.contains("archive") { return "archive" }
        if message.contains("playlist") || message.contains("media") { return "playlist" }
        if message.contains("sqlite") || message.contains("database") { return "database" }
        return "other"
    }

    static func isCancellation(_ error: Error) -> Bool {
        if let loadError = error as? BackupFileLoader.LoadError {
            return isCancellation(loadError.underlying)
        }
        if error is CancellationError { return true }
        let cause = error as NSError
        return (cause.domain == NSCocoaErrorDomain && cause.code == NSUserCancelledError) ||
            (cause.domain == NSURLErrorDomain && cause.code == NSURLErrorCancelled)
    }

    static func configure(_ scope: Scope, error: Error, context: Context) {
        let category = category(for: error)
        scope.setTag(value: context.operation, key: "operation")
        scope.setTag(value: context.stage, key: "stage")
        scope.setTag(value: category, key: "error_category")
        if let side = context.side { scope.setTag(value: side.rawValue, key: "merge_side") }
        // Keep Sentry's default cause grouping; separate operations and known
        // failure families instead of combining every Go code 1 into one issue.
        scope.setFingerprint(["{{ default }}", context.operation, context.stage, category])
        scope.setContext(value: context.details, key: "backup_operation")
    }
}

func captureError(_ error: Error, operation: String, stage: String,
                  side: MergeSide? = nil, details: [String: Any] = [:]) {
    guard !MergerDiagnostics.isCancellation(error) else { return }
    let original = (error as? BackupFileLoader.LoadError)?.underlying ?? error
    SentrySDK.capture(error: MergerDiagnostics.diagnosticError(original)) { scope in
        MergerDiagnostics.configure(scope, error: original, context: .init(
            operation: operation, stage: stage, side: side, details: details))
    }
}

func addBreadcrumb(_ message: String, data: [String: Any] = [:]) {
    let crumb = Breadcrumb()
    crumb.level = .info
    crumb.category = "merger-controller"
    crumb.message = message
    crumb.data = data
    SentrySDK.addBreadcrumb(crumb)
}
