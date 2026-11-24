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

    func testGroupingMessageRemovesUserSpecificParts() {
        let first = "validateIndependentMedia: open /private/var/mobile/Containers/Data/Application/"
            + "D52BC291-DE7C-4F7E-AC56-51088738790C/tmp/library-merger641762884/A9C3DF38.jpeg: "
            + "no such file or directory"
        let second = "validateIndependentMedia: open /private/var/mobile/Containers/Data/Application/"
            + "589DBA4B-71BF-4E1B-A6ED-14522E5137B3/tmp/library-merger3795999638/167BC68E: no such file or directory"

        XCTAssertEqual(Diagnostics.groupingMessage(first),
                       "validateIndependentMedia: open <path>: no such file or directory")
        XCTAssertEqual(Diagnostics.groupingMessage(first), Diagnostics.groupingMessage(second))
        XCTAssertEqual(Diagnostics.groupingMessage("Error while downloading catalog from https://app.jw-cdn.org/a/b: "
                                                   + "read tcp 10.0.0.2:5123->1.2.3.4:443: connection reset"),
                       "Error while downloading catalog from <url> read tcp <ip>-><ip>: connection reset")
        XCTAssertNotEqual(Diagnostics.groupingMessage("unexpected HTTP status 403"),
                          Diagnostics.groupingMessage("unexpected HTTP status 503"))
        XCTAssertEqual(Diagnostics.groupingMessage("open /tmp/Alice Backup.jwlibrary: permission denied"),
                       "open <path>: permission denied")
        XCTAssertEqual(Diagnostics.groupingMessage("open /tmp/Alice Backup.jwlibrary: permission denied"),
                       Diagnostics.groupingMessage("open /tmp/Bob Old Backup.jwlibrary: permission denied"))
        XCTAssertNotEqual(Diagnostics.groupingMessage("backup incompatible: schema version is too old"),
                          Diagnostics.groupingMessage("zip: not a valid zip file"))
    }

    func testUserProblemsAreNotReported() {
        let goError = { (message: String) in
            NSError(domain: "go", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        XCTAssertTrue(Diagnostics.isExpected(goError("backup incompatible: schema version is too old")))
        XCTAssertTrue(Diagnostics.isExpected(goError("zip: not a valid zip file")))
        XCTAssertTrue(Diagnostics.isExpected(goError("write /private/var/x.mp4: no space left on device")))
        XCTAssertTrue(Diagnostics.isExpected(NSError(domain: NSCocoaErrorDomain,
                                                     code: NSFileWriteOutOfSpaceError)))
        XCTAssertFalse(Diagnostics.isExpected(goError("validateIndependentMedia: hash mismatch")))
        // A file name that contains the text is not the error itself.
        XCTAssertFalse(Diagnostics.isExpected(
            goError("independent media hash mismatch for \"backup incompatible: x.jpg\"")))
        XCTAssertFalse(Diagnostics.isExpected(goError("open /x/no space left on device.jpg: permission denied")))
    }
}
