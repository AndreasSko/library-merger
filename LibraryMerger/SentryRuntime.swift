import Darwin
import Foundation
import Sentry

/// Keeps diagnostics opt-in and identifies the actual execution environment.
enum SentryRuntime {
    static var executionEnvironment: String {
        #if targetEnvironment(macCatalyst)
        return "mac_catalyst"
        #elseif targetEnvironment(simulator)
        return "simulator"
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac ? "ios_on_mac" : "ios_device"
        #endif
    }

    static func reportingEnabled(preference: Bool, arguments: [String],
                                 environment: [String: String]) -> Bool {
        #if DEBUG
        if arguments.contains("--playlist-ui-test") ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil {
            return false
        }
        #endif
        return preference
    }

    static func configure(_ options: Options, enabled: Bool,
                          runtime: String = executionEnvironment) {
        options.enabled = enabled
        options.dsn = "https://e46082df0a5343d0bfe1615b169834ff@o1083063.ingest.sentry.io/4504147949780992"
        options.enableAutoSessionTracking = false
        options.enableNetworkTracking = false
        options.initialScope = { scope in
            scope.setTag(value: runtime, key: "execution_environment")
            return scope
        }
    }

    @discardableResult
    static func preserveIgnoredBrokenPipe() -> Bool {
        // Go's Apple runtime ignores SIGPIPE using a function handler. Sentry's
        // signal monitor preserves SIG_IGN, but cannot recognize that function's
        // semantics. Make the same disposition explicit before installing it.
        // Other fatal signals and the SDK's crash/hang tracking stay enabled.
        let previous = signal(SIGPIPE, SIG_IGN)
        return unsafeBitCast(previous, to: UInt.self) !=
            unsafeBitCast(SIG_ERR, to: UInt.self)
    }
}

func setupSentry(enableSentry: Bool) {
    // Closing first matters when the user changes the preference: SDK teardown
    // restores the previous signal dispositions, so apply SIG_IGN afterwards.
    SentrySDK.close()
    SentryRuntime.preserveIgnoredBrokenPipe()
    SentrySDK.start { options in
        SentryRuntime.configure(options, enabled: SentryRuntime.reportingEnabled(
            preference: enableSentry,
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment))
    }
}
