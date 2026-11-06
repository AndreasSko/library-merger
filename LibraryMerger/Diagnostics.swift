import Darwin
import Foundation
import Sentry

func setupSentry(enableSentry: Bool) {
    // Closing first matters when the user changes the setting: closing the SDK
    // restores the previous signal handlers, so SIGPIPE is ignored afterwards.
    SentrySDK.close()
    // Go ignores SIGPIPE (a write to a closed connection then just fails), but
    // does so with its own handler, which Sentry reports as a crash. Sentry
    // leaves an explicit SIG_IGN alone.
    signal(SIGPIPE, SIG_IGN)

    SentrySDK.start { options in
        options.enabled = Diagnostics.reportingEnabled(preference: enableSentry,
                                                       environment: ProcessInfo.processInfo.environment)
        options.dsn = "https://e46082df0a5343d0bfe1615b169834ff@o1083063.ingest.sentry.io/4504147949780992"
        options.enableAutoSessionTracking = false
        options.enableNetworkTracking = false
        options.initialScope = { scope in
            scope.setTag(value: Diagnostics.executionEnvironment, key: "execution_environment")
            return scope
        }

        #if DEBUG
        options.beforeSend = { event in
            print("Sending: \(event)")
            return event
        }
        #endif
    }
}

/// Reports an error together with the operation and stage it happened in.
/// Cancellations are expected and not reported.
func captureError(_ error: Error, operation: String, stage: String,
                  side: MergeSide? = nil, details: [String: Any] = [:]) {
    guard !Diagnostics.isCancellation(error) else { return }
    SentrySDK.capture(error: Diagnostics.reportableError(error)) { scope in
        scope.setTag(value: operation, key: "operation")
        scope.setTag(value: stage, key: "stage")
        if let side {
            scope.setTag(value: side.rawValue, key: "merge_side")
        }
        // Group by where an error happens. Otherwise every Go error ends up
        // in the same "go Code 1" issue.
        scope.setFingerprint(["{{ default }}", operation, stage])
        if !details.isEmpty {
            scope.setContext(value: details, key: "details")
        }
    }
}

func addBreadcrumb(_ message: String, data: [String: Any] = [:]) {
    let crumb = Breadcrumb()
    crumb.level = SentryLevel.info
    crumb.category = "merger-controller"
    crumb.message = message
    if !data.isEmpty {
        crumb.data = data
    }
    SentrySDK.addBreadcrumb(crumb)
}

enum Diagnostics {
    static var executionEnvironment: String {
        #if targetEnvironment(macCatalyst)
        return "mac_catalyst"
        #elseif targetEnvironment(simulator)
        return "simulator"
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac ? "ios_on_mac" : "ios_device"
        #endif
    }

    /// Debug builds running tests never report, even if reporting was enabled
    /// on the simulator before.
    static func reportingEnabled(preference: Bool, environment: [String: String]) -> Bool {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return false
        }
        #endif
        return preference
    }

    /// Sentry shows an NSError's debug description as the error message, and
    /// otherwise only "Code: 1". Keep the original description there, so we see
    /// the actual reason, for example from Go.
    static func reportableError(_ error: Error) -> NSError {
        let original = error as NSError
        var userInfo = original.userInfo
        userInfo[NSLocalizedDescriptionKey] = original.localizedDescription
        if userInfo[NSDebugDescriptionErrorKey] == nil {
            userInfo[NSDebugDescriptionErrorKey] = original.localizedDescription
        }
        return NSError(domain: original.domain, code: original.code, userInfo: userInfo)
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
    }
}
