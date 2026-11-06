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
}
