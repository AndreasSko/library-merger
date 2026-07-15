//
//  LibraryMergerTests.swift
//  LibraryMergerTests
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import XCTest
@testable import LibraryMerger

class LibraryMergerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testDocumentIDBeyondInt32Decodes() throws {
        let data = #"{"Int64":4052170279,"Valid":true}"#.data(using: .utf8)!

        let documentID = try JSONDecoder().decode(NullInt64.self, from: data)

        XCTAssertEqual(documentID.int64, 4_052_170_279)
        XCTAssertTrue(documentID.valid)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
