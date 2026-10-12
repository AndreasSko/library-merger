import Sentry
import XCTest
@testable import LibraryMerger

final class MergerDiagnosticsTests: XCTestCase {
    func testNSErrorPreservesDescriptionsMetadataAndUnderlyingCause() {
        let underlying = NSError(domain: "sqlite", code: 19,
                                 userInfo: [NSLocalizedDescriptionKey: "Constraint failed"])
        let original = NSError(domain: "go", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Cannot import backup: invalid manifest",
            NSDebugDescriptionErrorKey: "Go import validation rejected manifest",
            NSUnderlyingErrorKey: underlying,
            "validationStage": "manifest"
        ])

        let result = MergerDiagnostics.diagnosticError(original)

        XCTAssertEqual(result.domain, "go")
        XCTAssertEqual(result.code, 1)
        XCTAssertEqual(result.localizedDescription, original.localizedDescription)
        XCTAssertEqual(result.userInfo[NSDebugDescriptionErrorKey] as? String,
                       "Go import validation rejected manifest")
        XCTAssertEqual(result.userInfo["validationStage"] as? String, "manifest")
        XCTAssertTrue((result.userInfo[NSUnderlyingErrorKey] as? NSError) === underlying)
    }

    func testSwiftLocalizedErrorReasonSurvivesNSErrorConversion() {
        let result = MergerDiagnostics.diagnosticError(FixtureError())

        XCTAssertEqual(result.localizedDescription, "Backup checksum does not match")
        XCTAssertEqual(result.userInfo[NSDebugDescriptionErrorKey] as? String,
                       "Backup checksum does not match")
        XCTAssertEqual(result.localizedFailureReason, "Manifest integrity check failed")
    }

    func testKnownFailureFamiliesRemainSeparate() {
        let cases: [FailureScenario] = [
            .init(name: "schema", error: goError("Backup incompatible: unsupported schema"), category: "schema"),
            .init(name: "manifest", error: goError("Invalid manifest checksum"), category: "manifest"),
            .init(name: "archive", error: goError("Cannot open zip archive"), category: "archive"),
            .init(name: "database", error: goError("SQLite database could not be read"), category: "database"),
            .init(name: "playlist", error: goError("Unsupported playlist media"), category: "playlist"),
            .init(name: "unclassified Go failure", error: goError("Unknown import failure"), category: "other"),
            .init(name: "download timeout", error: GeneralError.timeout(message: "Download timed out"),
                  category: "timeout"),
            .init(name: "missing file", error: NSError(domain: NSCocoaErrorDomain, code: 260), category: "file_access"),
            .init(name: "offline network", error: NSError(domain: NSURLErrorDomain, code: -1009), category: "network")
        ]
        for scenario in cases {
            XCTContext.runActivity(named: scenario.name) { _ in
                XCTAssertEqual(MergerDiagnostics.category(for: scenario.error), scenario.category,
                               scenario.name)
            }
        }
    }

    func testScopeContainsOperationAndSafeContextWithoutReplacingCauseGrouping() {
        let scope = Scope()
        let error = NSError(domain: "go", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest"])
        let details: [String: Any] = ["provider": "iCloud", "elapsed_seconds": 3.5, "file_exists": true]

        MergerDiagnostics.configure(scope, error: error,
                                    context: .init(operation: "import", stage: "go-import",
                                                   side: .leftSide, details: details))
        let serialized = scope.serialize()
        let tags = serialized["tags"] as? [String: String]

        XCTAssertEqual(tags?["operation"], "import")
        XCTAssertEqual(tags?["stage"], "go-import")
        XCTAssertEqual(tags?["merge_side"], "leftSide")
        XCTAssertEqual(tags?["error_category"], "manifest")
        XCTAssertEqual(serialized["fingerprint"] as? [String],
                       ["{{ default }}", "import", "go-import", "manifest"])
        let contexts = serialized["context"] as? [String: Any]
        let operation = contexts?["backup_operation"] as? [String: Any]
        XCTAssertEqual(operation?["provider"] as? String, "iCloud")
        XCTAssertEqual(operation?["elapsed_seconds"] as? Double, 3.5)
        XCTAssertEqual(operation?["file_exists"] as? Bool, true)
        XCTAssertEqual(Set(operation?.keys.map { $0 } ?? []), Set(details.keys))
    }

    func testExpectedCancellationIsRecognized() {
        for scenario in cancellationCases {
            XCTContext.runActivity(named: scenario.name) { _ in
                XCTAssertTrue(MergerDiagnostics.isCancellation(scenario.error), scenario.name)
            }
        }
        XCTAssertFalse(MergerDiagnostics.isCancellation(goError("Import rejected")),
                       "A Go import failure must remain reportable")
    }

    private var cancellationCases: [(name: String, error: Error)] {
        [
            ("Swift task cancellation", CancellationError()),
            ("Cocoa user cancellation", NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)),
            ("URL request cancellation", NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)),
            ("wrapped provider cancellation", BackupFileLoader.LoadError(
                underlying: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError),
                provider: .fileProvider, stage: "coordinated-copy", elapsedSeconds: 0))
        ]
    }

    func testSDKCaptureKeepsGoReasonUnderlyingChainAndSuppressesCancellation() {
        // The localhost DSN, isolated cache, no integrations and beforeSend's
        // nil return prevent this regression test from sending an event.
        SentrySDK.close()
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentry-diagnostics-test-" + UUID().uuidString)
        defer {
            SentrySDK.close()
            try? FileManager.default.removeItem(at: cache)
        }
        let captured = expectation(description: "Go failure reaches event builder")
        var eventCount = 0
        SentrySDK.start { options in
            configureIsolatedSDK(options, cache: cache)
            options.beforeSend = { event in
                eventCount += 1
                let values = event.exceptions?.compactMap { $0.value } ?? []
                XCTAssertTrue(values.contains { $0.contains("Cannot import backup: invalid manifest") })
                let underlying = event.exceptions?.first { $0.type == "sqlite" }
                XCTAssertEqual(underlying?.mechanism?.data?[NSLocalizedDescriptionKey] as? String,
                               "Constraint failed")
                XCTAssertEqual(event.tags?["operation"], "import")
                XCTAssertEqual(event.fingerprint, ["{{ default }}", "import", "go-import", "manifest"])
                captured.fulfill()
                return nil
            }
        }
        for scenario in cancellationCases {
            XCTContext.runActivity(named: scenario.name) { _ in
                captureError(scenario.error, operation: "import", stage: "download")
            }
        }
        let cause = NSError(domain: "sqlite", code: 19,
                            userInfo: [NSLocalizedDescriptionKey: "Constraint failed"])
        let error = NSError(domain: "go", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Cannot import backup: invalid manifest",
            NSUnderlyingErrorKey: cause
        ])
        captureError(error, operation: "import", stage: "go-import", side: .leftSide,
                     details: ["provider": "local"])
        wait(for: [captured], timeout: 2)
        XCTAssertEqual(eventCount, 1)
    }
}

private struct FixtureError: LocalizedError {
    var errorDescription: String? { "Backup checksum does not match" }
    var failureReason: String? { "Manifest integrity check failed" }
}

private func configureIsolatedSDK(_ options: Options, cache: URL) {
    options.dsn = "http://diagnostic-test@127.0.0.1:1/1"
    options.cacheDirectoryPath = cache.path
    options.integrations = []
    options.enableCrashHandler = false
    options.enableAutoSessionTracking = false
    options.enableNetworkTracking = false
    options.enableAutoPerformanceTracing = false
    options.enableAutoBreadcrumbTracking = false
    options.enableAppHangTracking = false
    options.enableWatchdogTerminationTracking = false
    options.sendClientReports = false
}

private func goError(_ message: String) -> NSError {
    NSError(domain: "go", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private struct FailureScenario {
    let name: String
    let error: Error
    let category: String
}
