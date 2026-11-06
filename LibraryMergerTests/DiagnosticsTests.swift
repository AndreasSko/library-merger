import XCTest
@testable import LibraryMerger

final class DiagnosticsTests: XCTestCase {
    func testReportableErrorKeepsTheReason() {
        // Gomobile errors only carry their message as localized description.
        let goError = NSError(domain: "go", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "backup incompatible: schema 99"])

        let reportable = Diagnostics.reportableError(goError)

        XCTAssertEqual(reportable.domain, "go")
        XCTAssertEqual(reportable.code, 1)
        XCTAssertEqual(reportable.userInfo[NSDebugDescriptionErrorKey] as? String, "backup incompatible: schema 99")
        XCTAssertEqual(reportable.localizedDescription, "backup incompatible: schema 99")
    }

    func testReportableErrorKeepsUnderlyingError() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                            userInfo: [NSUnderlyingErrorKey: underlying])

        let reportable = Diagnostics.reportableError(error)

        XCTAssertEqual(reportable.userInfo[NSUnderlyingErrorKey] as? NSError, underlying)
        XCTAssertNotNil(reportable.userInfo[NSDebugDescriptionErrorKey])
    }

    func testCancellationsAreRecognized() {
        XCTAssertTrue(Diagnostics.isCancellation(CancellationError()))
        XCTAssertTrue(Diagnostics.isCancellation(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        XCTAssertTrue(Diagnostics.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(Diagnostics.isCancellation(NSError(domain: "go", code: 1)))
    }

    func testTestsNeverReport() {
        XCTAssertFalse(Diagnostics.reportingEnabled(preference: true,
                                                    environment: ["XCTestConfigurationFilePath": "/x"]))
        XCTAssertTrue(Diagnostics.reportingEnabled(preference: true, environment: [:]))
        XCTAssertFalse(Diagnostics.reportingEnabled(preference: false, environment: [:]))
    }
}
