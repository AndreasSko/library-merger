//
//  LibraryMergerTests.swift
//  LibraryMergerTests
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import XCTest
@testable import LibraryMerger

@MainActor
class LibraryMergerTests: XCTestCase {

    func testDocumentIDBeyondInt32Decodes() throws {
        let data = Data(#"{"Int64":4052170279,"Valid":true}"#.utf8)

        let documentID = try JSONDecoder().decode(NullInt64.self, from: data)

        XCTAssertEqual(documentID.int64, 4_052_170_279)
        XCTAssertTrue(documentID.valid)
    }

}
extension LibraryMergerTests {
    func testMixedNativeAndCanonicalHashesPreserveRepeatedMedia() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("mixed-hashes"), side: .leftSide)
        try await controller.importBackup(url: fixture("mixed-hashes"), side: .rightSide)
        XCTAssertEqual(controller.dbWrapper.stats("leftSide")?.playlistItem, 2)
        try await controller.merge(progress: MergeProgress())
        XCTAssertEqual(controller.dbWrapper.stats("mergeSide")?.playlistItem, 2)
        try await saveExport(controller, name: "mixed-hashes")
    }

    func testResetRejectsQueuedImportAndExport() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        let abandonedSession = controller.sessionID
        controller.resetSession()
        let currentSession = controller.sessionID
        do {
            try await controller.importBackup(url: fixture("base"), side: .leftSide, sessionID: abandonedSession)
            XCTFail("Queued import must not load a replacement session")
        } catch { }
        XCTAssertFalse(controller.dbWrapper.dbIsLoaded("leftSide"))
        XCTAssertEqual(controller.sessionID, currentSession)
        XCTAssertFalse(controller.isBusy)
        try await controller.importBackup(url: fixture("base"), side: .leftSide, sessionID: currentSession)
        try await controller.importBackup(url: fixture("empty"), side: .rightSide, sessionID: currentSession)
        try await controller.merge(progress: MergeProgress(), sessionID: currentSession)
        let validExport = try await controller.exportBackup(sessionID: currentSession)
        let before = try Data(contentsOf: URL(fileURLWithPath: validExport))
        let directory = URL(fileURLWithPath: validExport).deletingLastPathComponent()
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        do {
            _ = try await controller.exportBackup(sessionID: abandonedSession)
            XCTFail("Queued export must not export or clean files from a replacement session")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: validExport)), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), filesBefore)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(controller.sessionID, currentSession)
    }

    func testRepeatedPlaylistOccurrencesSurviveExport() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("repeated-aba"), side: .leftSide)
        try await controller.importBackup(url: fixture("repeated-abaa"), side: .rightSide)
        try await controller.merge(progress: MergeProgress())
        XCTAssertEqual(controller.dbWrapper.stats("mergeSide")?.playlistItem, 4)
        try await saveExport(controller, name: "repeated-aba-abaa")
    }

    func testThumbnailChangesMergeWithoutPrompt() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("thumbnail-old"), side: .leftSide)
        try await controller.importBackup(url: fixture("thumbnail-new"), side: .rightSide)
        try await controller.merge(progress: MergeProgress())
        XCTAssertNil(controller.conflictResolutionID)
        try await saveExport(controller, name: "thumbnail-auto")
    }

    func testSameThumbnailBytesAndNativeHashesMergeWithoutConflict() async throws {
        for other in ["thumbnail-same-bytes", "thumbnail-unpadded"] {
            let controller = MergerController()
            defer { controller.resetSession() }
            try await controller.importBackup(url: fixture("thumbnail-old"), side: .leftSide)
            try await controller.importBackup(url: fixture(other), side: .rightSide)
            try await controller.merge(progress: MergeProgress())
            XCTAssertNil(controller.conflictResolutionID)
            try await saveExport(controller, name: other)
        }
    }

    @MainActor
    func testCancelledConflictCannotResumeRetry() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("conflict"), side: .rightSide)
        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected a conflict")
        } catch MergeError.mergeConflict { }
        let cancelled = try XCTUnwrap(controller.conflictResolutionID)
        let oldConflict = try controller.nextConflict(resolutionID: cancelled)
        do {
            _ = try await controller.exportBackup()
            XCTFail("Unresolved conflict must block export")
        } catch { }
        controller.cancelConflictResolution(cancelled)
        XCTAssertNil(controller.conflictResolutionID)
        do {
            _ = try await controller.exportBackup()
            XCTFail("Cancellation must not make the partial merge exportable")
        } catch { }
        XCTAssertTrue(controller.dbWrapper.dbIsLoaded("leftSide"))
        XCTAssertTrue(controller.dbWrapper.dbIsLoaded("rightSide"))
        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Retry must ask for the cancelled choice again")
        } catch MergeError.mergeConflict { }
        let retry = try XCTUnwrap(controller.conflictResolutionID)
        XCTAssertNotEqual(retry, cancelled)
        XCTAssertThrowsError(try controller.solveConflict(oldConflict.key, side: .rightSide, resolutionID: cancelled))
        do {
            try await controller.merge(reset: false, progress: MergeProgress(), resolutionID: cancelled)
            XCTFail("Dismissal of an old presentation must not resume a new conflict")
        } catch { }
        XCTAssertEqual(controller.conflictResolutionID, retry)
        let current = try controller.nextConflict(resolutionID: retry)
        try controller.solveConflict(current.key, side: .rightSide, resolutionID: retry)
        try await controller.merge(reset: false, progress: MergeProgress(), resolutionID: retry)
        XCTAssertNil(controller.conflictResolutionID)
        try await saveExport(controller, name: "cancel-retry")
        try await saveExport(controller, name: "cancel-retry-again")
    }

    func testResetRejectsAbandonedConflictAndAcceptsNewInputs() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("conflict"), side: .rightSide)
        do { try await controller.merge(progress: MergeProgress()) } catch MergeError.mergeConflict { }
        let abandoned = try XCTUnwrap(controller.conflictResolutionID)
        let session = controller.sessionID
        controller.resetSession()
        XCTAssertNotEqual(controller.sessionID, session)
        XCTAssertNil(controller.conflictResolutionID)
        XCTAssertFalse(controller.dbWrapper.dbIsLoaded("leftSide"))
        XCTAssertFalse(controller.dbWrapper.dbIsLoaded("rightSide"))
        XCTAssertThrowsError(try controller.nextConflict(resolutionID: abandoned))
        do {
            try await controller.merge(reset: false, progress: MergeProgress(), resolutionID: abandoned)
            XCTFail("Reset session must reject a pending presentation callback")
        } catch { }
        XCTAssertFalse(controller.isBusy)
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("empty"), side: .rightSide)
        try await controller.merge(progress: MergeProgress())
        try await saveExport(controller, name: "reset-after-conflict")
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jwlibrary",
                                                subdirectory: "Fixtures"))
    }

    func testUnknownConflictTypeThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(Model.self, from: Data(#"{"type":"FutureModel"}"#.utf8)))
    }

    func testPlaylistMergeRetryAndRepeatedExport() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("conflict"), side: .rightSide)
        XCTAssertEqual(controller.dbWrapper.stats("leftSide")?.playlist, 1)
        XCTAssertEqual(controller.dbWrapper.stats("leftSide")?.playlistItem, 3)
        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected an item conflict")
        } catch MergeError.mergeConflict { }
        let conflict = try controller.nextConflict()
        guard case .playlistItem(let item) = conflict.right?.model else {
            return XCTFail("Expected a decodable playlist item")
        }
        XCTAssertEqual(item.label, "Changed A")
        XCTAssertEqual(item.startTrimOffsetTicks.int64, 2_500_000_000)
        XCTAssertEqual(conflict.right?.related.tag?.name, "Common")
        XCTAssertEqual(conflict.right?.related.independentMedia?.originalFilename, "A.bin")
        try controller.mergeConflicts.solveConflict(conflict.key, side: "rightSide")
        try await controller.merge(reset: false, progress: MergeProgress())
        try await saveExport(controller, name: "conflict")
        try await saveExport(controller, name: "conflict-again")
        // Cancelling a conflict and starting again must keep the imported media.
        do { try await controller.merge(progress: MergeProgress()) } catch MergeError.mergeConflict { }
        let retried = try controller.nextConflict()
        try controller.mergeConflicts.solveConflict(retried.key, side: "leftSide")
        try await controller.merge(reset: false, progress: MergeProgress())
        try await saveExport(controller, name: "conflict-left")
    }

    func testPlaylistDurationConflict() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("duration"), side: .rightSide)
        do { try await controller.merge(progress: MergeProgress()) } catch MergeError.mergeConflict { }
        let conflict = try controller.nextConflict()
        guard case .playlistItemIndependentMediaMap(let mapping) = conflict.right?.model else {
            return XCTFail("Expected a media-duration conflict")
        }
        XCTAssertEqual(mapping.durationTicks, 6_000_000_000)
        XCTAssertEqual(conflict.right?.related.tag?.name, "Common")
        XCTAssertEqual(conflict.right?.related.playlistItem?.label, "A")
        try controller.mergeConflicts.solveConflict(conflict.key, side: "rightSide")
        try await controller.merge(reset: false, progress: MergeProgress())
        try await saveExport(controller, name: "duration")
    }

    func testPlaylistImportFailureAndReset() async throws {
        let controller = MergerController()
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        do {
            let directory = Bundle(for: Self.self).resourceURL!.appendingPathComponent("Fixtures")
            try await controller.importBackup(url: directory, side: .leftSide)
            XCTFail("Expected failed import")
        } catch { }
        XCTAssertEqual(controller.dbWrapper.stats("leftSide")?.playlistItem, 3)
        controller.resetSession()
        XCTAssertFalse(controller.dbWrapper.dbIsLoaded("leftSide"))
    }

    func testUnsupportedPlaylistImportKeepsPreviousBackup() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        do {
            try await controller.importBackup(url: fixture("unsupported"), side: .leftSide)
            XCTFail("Unsupported playlist must not be silently skipped")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("multiple locations"))
        }
        XCTAssertEqual(controller.dbWrapper.stats("leftSide")?.playlistItem, 3)
    }

    func testPlaylistLocationConflictDecodes() throws {
        let json = #"{"type":"PlaylistItemLocationMap","playlistItemId":1,"locationId":2,"majorMultimediaType":2,"#
            + #""baseDurationTicks":{"Int64":6000000000,"Valid":true}}"#
        let data = Data(json.utf8)
        guard case .playlistItemLocationMap(let mapping) = try JSONDecoder().decode(Model.self, from: data) else {
            return XCTFail("Expected a location mapping")
        }
        XCTAssertEqual(mapping.baseDurationTicks.int64, 6_000_000_000)
    }

    func testPlaylistReorderIsRejected() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        try await controller.importBackup(url: fixture("base"), side: .leftSide)
        try await controller.importBackup(url: fixture("reordered"), side: .rightSide)
        controller.settings = MergeSettings(bookmarkResolver: .chooseLeft, markingResolver: .chooseLeft,
                                            noteResolver: .chooseLeft, inputFieldResolver: .chooseLeft)
        // Resolve differing end actions first; order itself must remain an error.
        for attempt in 0..<5 {
            do {
                try await controller.merge(reset: attempt == 0, progress: MergeProgress())
                return XCTFail("Contradictory ordering must not succeed")
            } catch MergeError.mergeConflict {
                while let conflict = try? controller.nextConflict() {
                    try controller.mergeConflicts.solveConflict(conflict.key, side: "leftSide")
                }
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("contradictory reorders"))
                return
            }
        }
        XCTFail("Merge never reported contradictory ordering")
    }

    func testPlaylistFrontAndEmpty() async throws {
        for other in ["front", "empty"] {
            let controller = MergerController()
            defer { controller.resetSession() }
            try await controller.importBackup(url: fixture("base"), side: .leftSide)
            try await controller.importBackup(url: fixture(other), side: .rightSide)
            try await controller.merge(progress: MergeProgress())
            try await saveExport(controller, name: other)
        }
    }

    func testOriginalPlaylistArchives() async throws {
        let root = Bundle(for: Self.self).resourceURL!.appendingPathComponent("Fixtures/Original")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("Optional original archives are not bundled; see scripts/README-playlists.md")
        }
        let cases = [
            ("scenario-1-insert-front", "base", "add-front"),
            ("scenario-2-divergent-inserts", "left-add-photo-front", "right-add-video-middle"),
            ("scenario-3-separate-playlists", "left-playlist-a", "right-playlist-b"),
            ("scenario-4-common-plus-new", "left-common-and-new", "right-common-and-new")
        ]
        for (folder, left, right) in cases {
            for reverse in [false, true] {
                let controller = MergerController()
                defer { controller.resetSession() }
                let directory = root.appendingPathComponent(folder)
                try await controller.importBackup(url: directory.appendingPathComponent(
                    "\(reverse ? right : left).jwlibrary"), side: .leftSide)
                try await controller.importBackup(url: directory.appendingPathComponent(
                    "\(reverse ? left : right).jwlibrary"), side: .rightSide)
                try await controller.merge(progress: MergeProgress())
                try await saveExport(controller, name: folder + (reverse ? "-reverse" : ""))
            }
        }
    }

    private func saveExport(_ controller: MergerController, name: String) async throws {
        let exported = try await controller.exportBackup()
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaylistValidation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let destination = output.appendingPathComponent(name + ".jwlibrary")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(atPath: exported, toPath: destination.path)
        XCTAssertGreaterThan(try Data(contentsOf: destination).count, 0)
    }
}
