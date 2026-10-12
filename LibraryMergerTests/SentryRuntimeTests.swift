import Darwin
import Sentry
import XCTest
@testable import LibraryMerger

final class SentryRuntimeTests: XCTestCase {
    func testBrokenPipeIsIgnoredWithoutChangingOtherCrashSignals() throws {
        var originalPipe = sigaction()
        var originalAbort = sigaction()
        XCTAssertEqual(sigaction(SIGPIPE, nil, &originalPipe), 0)
        XCTAssertEqual(sigaction(SIGABRT, nil, &originalAbort), 0)
        defer { sigaction(SIGPIPE, &originalPipe, nil) }

        XCTAssertTrue(SentryRuntime.preserveIgnoredBrokenPipe())
        var currentPipe = sigaction()
        var currentAbort = sigaction()
        XCTAssertEqual(sigaction(SIGPIPE, nil, &currentPipe), 0)
        XCTAssertEqual(sigaction(SIGABRT, nil, &currentAbort), 0)
        XCTAssertEqual(unsafeBitCast(currentPipe.__sigaction_u.__sa_handler, to: UInt.self),
                       unsafeBitCast(SIG_IGN, to: UInt.self))
        XCTAssertEqual(unsafeBitCast(currentAbort.__sigaction_u.__sa_handler, to: UInt.self),
                       unsafeBitCast(originalAbort.__sigaction_u.__sa_handler, to: UInt.self))
        // No SDK or transport is started; a broken pipe cannot terminate this process.
        XCTAssertEqual(raise(SIGPIPE), 0)
    }

    func testSDKCrashMonitorPreservesIgnoredBrokenPipe() throws {
        // Restrict startup to the real crash integration, with an empty isolated
        // cache and a localhost DSN. Never construct a production transport.
        SentrySDK.close()
        var originalPipe = sigaction()
        var originalAbort = sigaction()
        XCTAssertEqual(sigaction(SIGPIPE, nil, &originalPipe), 0)
        XCTAssertEqual(sigaction(SIGABRT, nil, &originalAbort), 0)
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentry-signal-test-" + UUID().uuidString)
        defer {
            SentrySDK.close()
            sigaction(SIGPIPE, &originalPipe, nil)
            sigaction(SIGABRT, &originalAbort, nil)
            try? FileManager.default.removeItem(at: cache)
        }
        XCTAssertTrue(SentryRuntime.preserveIgnoredBrokenPipe())
        SentrySDK.start { options in
            options.dsn = "http://signal-test@127.0.0.1:1/1"
            options.cacheDirectoryPath = cache.path
            options.integrations = ["SentryCrashIntegration"]
            options.enableCrashHandler = true
            options.enableAutoSessionTracking = false
            options.enableNetworkTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
            options.sendClientReports = false
            options.beforeSend = { _ in nil }
        }
        var monitoredPipe = sigaction()
        var monitoredAbort = sigaction()
        XCTAssertEqual(sigaction(SIGPIPE, nil, &monitoredPipe), 0)
        XCTAssertEqual(sigaction(SIGABRT, nil, &monitoredAbort), 0)
        XCTAssertEqual(unsafeBitCast(monitoredPipe.__sigaction_u.__sa_handler, to: UInt.self),
                       unsafeBitCast(SIG_IGN, to: UInt.self))
        // This proves the signal monitor installed rather than passing because
        // the entire SDK or crash integration was disabled.
        XCTAssertNotEqual(unsafeBitCast(monitoredAbort.__sigaction_u.__sa_handler, to: UInt.self),
                          unsafeBitCast(originalAbort.__sigaction_u.__sa_handler, to: UInt.self))
        XCTAssertEqual(raise(SIGPIPE), 0)
    }

    func testConfigurationPreservesOptInAndOtherDiagnostics() {
        let options = Options()
        SentryRuntime.configure(options, enabled: false)
        XCTAssertFalse(options.enabled)
        SentryRuntime.configure(options, enabled: true)
        XCTAssertTrue(options.enabled)
        XCTAssertFalse(options.enableAutoSessionTracking)
        XCTAssertFalse(options.enableNetworkTracking)
        XCTAssertTrue(options.enableCrashHandler)
        XCTAssertTrue(options.enableAppHangTracking)
    }

    func testTestProcessesCannotEnableReporting() {
        var cases: [ReportingScenario] = [
            .init(name: "user opted out", preference: false, arguments: [], environment: [:], enabled: false),
            .init(name: "user opted in", preference: true, arguments: [], environment: [:], enabled: true)
        ]
        #if DEBUG
        cases += [
            .init(name: "fictional UI test launch", preference: true, arguments: ["--playlist-ui-test"],
                  environment: [:], enabled: false),
            .init(name: "XCTest process", preference: true, arguments: [],
                  environment: ["XCTestConfigurationFilePath": "fixture"], enabled: false)
        ]
        #endif
        for scenario in cases {
            XCTContext.runActivity(named: scenario.name) { _ in
                XCTAssertEqual(SentryRuntime.reportingEnabled(preference: scenario.preference,
                    arguments: scenario.arguments, environment: scenario.environment),
                    scenario.enabled, scenario.name)
            }
        }
    }

    func testRuntimeTagDistinguishesExecutionEnvironment() {
        let options = Options()
        SentryRuntime.configure(options, enabled: false, runtime: "ios_on_mac")
        let scope = options.initialScope(Scope())
        XCTAssertEqual(scope.serialize()["tags"] as? [String: String],
                       ["execution_environment": "ios_on_mac"])
        XCTAssertTrue(["mac_catalyst", "simulator", "ios_on_mac", "ios_device"]
            .contains(SentryRuntime.executionEnvironment))
    }
}

private struct ReportingScenario {
    let name: String
    let preference: Bool
    let arguments: [String]
    let environment: [String: String]
    let enabled: Bool
}
