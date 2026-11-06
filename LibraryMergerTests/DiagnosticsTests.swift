import XCTest
@testable import LibraryMerger

final class DiagnosticsTests: XCTestCase {
    func testTestsNeverReport() {
        XCTAssertFalse(Diagnostics.reportingEnabled(preference: true,
                                                    environment: ["XCTestConfigurationFilePath": "/x"]))
        XCTAssertTrue(Diagnostics.reportingEnabled(preference: true, environment: [:]))
        XCTAssertFalse(Diagnostics.reportingEnabled(preference: false, environment: [:]))
    }
}
