//
//  LibraryMergerTests.swift
//  LibraryMergerTests
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import XCTest
@testable import LibraryMerger

class LibraryMergerTests: XCTestCase {

    func testDocumentIDBeyondInt32Decodes() throws {
        let data = Data(#"{"Int64":4052170279,"Valid":true}"#.utf8)

        let documentID = try JSONDecoder().decode(NullInt64.self, from: data)

        XCTAssertEqual(documentID.int64, 4_052_170_279)
        XCTAssertTrue(documentID.valid)
    }

    func testUnknownConflictTypeThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(Model.self, from: Data(#"{"type":"FutureModel"}"#.utf8)))
    }

    func testPlaylistConflictCanBeResolvedAndExported() async throws {
        let controller = MergerController()
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("conflict"), side: .rightSide)

        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected a playlist conflict")
        } catch MergeError.mergeConflict { }

        let conflict = try controller.nextConflict()
        guard case .playlistItem(let item) = conflict.right?.model else {
            return XCTFail("Expected a playlist item conflict")
        }
        XCTAssertEqual(item.label, "Changed A")
        XCTAssertEqual(conflict.changedFields, [.label, .endAction])
        XCTAssertEqual(conflict.right?.related.tag?.name, "Common")
        XCTAssertEqual(conflict.right?.related.independentMedia?.originalFilename, "A.bin")

        try controller.mergeConflicts.solveConflict(conflict.key, side: MergeSide.rightSide.rawValue)
        try await controller.merge(reset: false, progress: MergeProgress())
        XCTAssertEqual(controller.dbWrapper.stats("mergeSide")?.playlistItem, 3)
        let exported = try await controller.exportBackup()
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported))
    }

    func testPlaylistConflictCanBeResolvedAutomatically() async throws {
        let controller = MergerController()
        controller.settings.playlistResolver = .chooseRight
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("conflict"), side: .rightSide)

        try await controller.merge(progress: MergeProgress())
        XCTAssertEqual(controller.dbWrapper.stats("mergeSide")?.playlistItem, 3)
    }

    func testPlaylistDurationConflict() async throws {
        let controller = MergerController()
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("duration"), side: .rightSide)

        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected a playlist conflict")
        } catch MergeError.mergeConflict { }

        let conflict = try controller.nextConflict()
        XCTAssertEqual(conflict.changedFields, [.durationTicks])
        XCTAssertEqual(conflict.right?.related.playlistItem?.label, "A")
        let right = try XCTUnwrap(conflict.right?.model)
        XCTAssertEqual(PlaylistChangedField.durationTicks.value(in: right),
                       600.formatted(.number.precision(.fractionLength(0...7))) + " s")
    }

    func testPlaylistConflictShowsThumbnail() async throws {
        let controller = MergerController()
        try await controller.importBackup(url: fixture("publication-base"), side: .leftSide)
        try await controller.importBackup(url: fixture("publication-action"), side: .rightSide)

        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected a playlist conflict")
        } catch MergeError.mergeConflict { }

        XCTAssertNotNil(try controller.nextConflict().thumbnail)
    }

    func testUnsupportedPlaylistsAreSkipped() async throws {
        let controller = MergerController()
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("unsupported"), side: .rightSide)

        XCTAssertFalse(controller.dbWrapper.dbContainsUnsupportedPlaylists(MergeSide.leftSide.rawValue))
        XCTAssertTrue(controller.dbWrapper.dbContainsUnsupportedPlaylists(MergeSide.rightSide.rawValue))
        XCTAssertEqual(controller.dbWrapper.stats(MergeSide.rightSide.rawValue)?.playlistItem, 0)

        try await controller.merge(progress: MergeProgress())
        XCTAssertEqual(controller.dbWrapper.stats("mergeSide")?.playlistItem, 3)
    }

    func testMarkingConflictShowsMarkedText() async throws {
        let controller = MergerController()
        // A cached publication keeps the test offline
        controller.publicationCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: controller.publicationCacheDir,
                                                withIntermediateDirectories: true)
        let paragraph = "One two three four five six seven eight nine ten "
            + "eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty."
        try Data(#"{"2025405":{"7":{"text":"\#(paragraph)","number":1}}}"#.utf8)
            .write(to: controller.publicationCacheDir.appendingPathComponent("w_E_20250500.json"))
        try await controller.importBackup(url: fixture("marking-left"), side: .leftSide)
        try await controller.importBackup(url: fixture("marking-right"), side: .rightSide)

        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected a marking conflict")
        } catch MergeError.mergeConflict { }

        let conflict = try controller.nextConflict()
        let left = try await controller.markingSnippets(key: conflict.key, side: .leftSide)
        let right = try await controller.markingSnippets(key: conflict.key, side: .rightSide)
        XCTAssertEqual(left, [MarkingSnippet(before: "One two three four five six seven eight nine ",
                                             marked: "ten eleven twelve thirteen fourteen",
                                             after: " fifteen sixteen seventeen eighteen nineteen twenty.",
                                             number: 1, heading: nil)])
        XCTAssertEqual(right.first?.marked, "thirteen fourteen fifteen sixteen seventeen eighteen nineteen")
    }

    func testPlaylistChangedFieldValues() throws {
        let json = #"{"type":"PlaylistItem","playlistItemId":1,"label":"Excerpt","#
            + #""startTrimOffsetTicks":{"Int64":25000000,"Valid":true},"#
            + #""endTrimOffsetTicks":{"Int64":0,"Valid":false},"accuracy":1,"endAction":3,"#
            + #""thumbnailFilePath":{"String":"","Valid":false}}"#
        let item = try JSONDecoder().decode(Model.self, from: Data(json.utf8))

        XCTAssertEqual(PlaylistChangedField.label.value(in: item), "Excerpt")
        XCTAssertEqual(PlaylistChangedField.endAction.value(in: item), NSLocalizedString("Repeat", comment: ""))
        XCTAssertEqual(PlaylistChangedField.endTrimOffsetTicks.value(in: item),
                       NSLocalizedString("Not set", comment: ""))
        XCTAssertNil(PlaylistChangedField.durationTicks.value(in: item))
        XCTAssertEqual(PlaylistChangedField.startTrimOffsetTicks.value(in: item),
                       2.5.formatted(.number.precision(.fractionLength(0...7))) + " s")
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jwlibrary",
                                                subdirectory: "Fixtures"))
    }
}
