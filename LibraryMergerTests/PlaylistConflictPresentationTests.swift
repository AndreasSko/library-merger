import XCTest
import SwiftUI
@testable import LibraryMerger

@MainActor
final class PlaylistConflictPresentationTests: XCTestCase {
    private var item: Model {
        get throws {
            let json = #"{"type":"PlaylistItem","playlistItemId":1,"label":"Excerpt","#
                + #""startTrimOffsetTicks":{"Int64":25000000,"Valid":true},"#
                + #""endTrimOffsetTicks":{"Int64":0,"Valid":false},"accuracy":1,"endAction":3,"#
                + #""thumbnailFilePath":{"String":"preview.png","Valid":true}}"#
            return try JSONDecoder().decode(Model.self, from: Data(json.utf8))
        }
    }

    func testSingleChangedFieldOmitsUnchangedSettingsAndContext() throws {
        let presentation = try PlaylistConflictPresentation(changedFieldsJSON: #"["endAction"]"#, model: item)
        let rows = try presentation.rows(for: item)
        XCTAssertEqual(rows.map(\.field), [.endAction])
        XCTAssertEqual(rows.map(\.value), [NSLocalizedString("Repeat", comment: "")])
        XCTAssertEqual(presentation.question, "What should happen when this item finishes?")
        XCTAssertFalse(presentation.choosesWholeVersion)
        XCTAssertFalse(rows.contains { $0.field == .startTrimOffsetTicks || $0.field == .label })
    }

    func testMultipleChangedFieldsKeepWholeVersionSemantics() throws {
        let presentation = try PlaylistConflictPresentation(changedFieldsJSON: #"["label","endAction"]"#, model: item)
        XCTAssertEqual(try presentation.rows(for: item).map(\.field), [.label, .endAction])
        XCTAssertEqual(presentation.question, "Which settings should this item use?")
        XCTAssertTrue(presentation.choosesWholeVersion)
    }

    func testMediaTypesHaveHumanLabelsAndPreserveUnknownValue() throws {
        for (type, expected) in [(1, "Audio"), (2, "Video"), (99, "Unknown (99)")] {
            let json = #"{"type":"PlaylistItemLocationMap","playlistItemId":1,"locationId":1,"#
                + #""majorMultimediaType":\#(type),"baseDurationTicks":{"Int64":0,"Valid":false}}"#
            let model = try JSONDecoder().decode(Model.self, from: Data(json.utf8))
            let value = try PlaylistChangedField.majorMultimediaType.value(in: model)
            let localized = type == 99
                ? String(format: NSLocalizedString("Unknown (%@)", comment: ""), String(type))
                : NSLocalizedString(expected, comment: "")
            XCTAssertEqual(value, localized)
        }
    }

    func testTimeFormattingPreservesExactTicksAndIntegerLimits() {
        let expected: [(Int64, String)] = [
            (0, "0.000 s"), (10_000_000, "1.000 s"), (10_000_001, "1.0000001 s"),
            (25_000_000, "2.500 s"), (-1, "-0.0000001 s"), (-10_000_001, "-1.0000001 s"),
            (.max, "922337203685.4775807 s"), (.min, "-922337203685.4775808 s")
        ]
        for (ticks, value) in expected { XCTAssertEqual(formatPlaylistTicks(ticks), value) }
        XCTAssertNotEqual(formatPlaylistTicks(10_000_000), formatPlaylistTicks(10_000_001))
    }

    func testUnknownEmptyDuplicateOrWrongModelMetadataFailsVisibly() throws {
        let invalid = [#"["futureField"]"#, "[]", #"["endAction","endAction"]"#, #"["durationTicks"]"#, "invalid"]
        for json in invalid {
            XCTAssertThrowsError(try PlaylistConflictPresentation(changedFieldsJSON: json, model: item)) { error in
                XCTAssertEqual(error.localizedDescription,
                               PlaylistConflictPresentation.invalidMetadata.localizedDescription)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testSourceLinksRequireGoSuppliedHTTPSJWDomain() {
        XCTAssertEqual(PlaylistSourceLink.validatedURL("https://www.jw.org/finder?item=video")?.host, "www.jw.org")
        for source in [nil, "", "http://www.jw.org/video", "https://jw.org.example.com/video",
                       "https://jw.org@evil.example/video", "https://user@www.jw.org/video"] {
            XCTAssertNil(PlaylistSourceLink.validatedURL(source))
        }
    }

    func testMissingSourceMetadataDoesNotGuessLink() throws {
        let json = #"{"model":{"type":"PlaylistItem","playlistItemId":1,"label":"Unknown source","#
            + #""startTrimOffsetTicks":{"Int64":0,"Valid":false},"#
            + #""endTrimOffsetTicks":{"Int64":0,"Valid":false},"accuracy":1,"endAction":0,"#
            + #""thumbnailFilePath":{"String":"","Valid":false}},"related":{}}"#
        let tuple = try JSONDecoder().decode(ModelRelatedTuple.self, from: Data(json.utf8))
        XCTAssertNil(tuple.sourceURL)
        XCTAssertNil(PlaylistSourceLink.validatedURL(tuple.sourceURL))
    }

    func testPublicationActionConflictDisplaysOnlyEndAction() async throws {
        let controller = try await conflictedController(left: "publication-base", right: "publication-action")
        defer { controller.resetSession() }
        let conflict = try controller.nextConflict()
        let presentation = try XCTUnwrap(conflict.playlistPresentation)
        XCTAssertEqual(presentation.fields, [.endAction])
        let left = try XCTUnwrap(conflict.left)
        let right = try XCTUnwrap(conflict.right)
        XCTAssertEqual(left.related.location?.title.string, "JW Broadcasting—October 2026")
        let context = PlaylistContextPresentation(related: left.related, publication: nil, itemTitle: nil)
        XCTAssertEqual(context.rows.map(\.key), ["Title:", "Playlist:"])
        XCTAssertEqual(context.rows.first?.value, "JW Broadcasting—October 2026")
        XCTAssertFalse(context.rows.contains { $0.key == "Document ID:" || $0.key == "Track:" })
        XCTAssertEqual(left.sourceURL, "https://www.jw.org/finder?lank=pub-jwb-142_1_VIDEO&wtlocale=E")
        XCTAssertNotNil(PlaylistSourceLink.validatedURL(left.sourceURL))
        XCTAssertEqual(try presentation.rows(for: left.model).map(\.value),
                       [NSLocalizedString("Play next", comment: "")])
        XCTAssertEqual(try presentation.rows(for: right.model).map(\.value), [NSLocalizedString("Repeat", comment: "")])
        try await captureConflict(controller, name: "publication-action-conflict")
        try controller.mergeConflicts.solveConflict(conflict.key, side: "rightSide")
        try await controller.merge(reset: false, progress: MergeProgress())
        try await saveExport(controller, name: "publication-action")
    }

    func testPublicationThumbnailDifferenceNeedsNoChoice() async throws {
        let controller = MergerController()
        defer { controller.resetSession() }
        let bundle = Bundle(for: Self.self)
        let left = try XCTUnwrap(bundle.url(forResource: "publication-base", withExtension: "jwlibrary",
                                           subdirectory: "Fixtures"))
        let right = try XCTUnwrap(bundle.url(forResource: "publication-thumbnail-new", withExtension: "jwlibrary",
                                            subdirectory: "Fixtures"))
        try await controller.importBackup(url: left, side: .leftSide)
        try await controller.importBackup(url: right, side: .rightSide)
        try await controller.merge(progress: MergeProgress())
        XCTAssertNil(controller.conflictResolutionID)
        try await saveExport(controller, name: "publication-thumbnail")
    }

    func testBinaryConflictDisplaysOnlyGoSuppliedDifferences() async throws {
        let controller = try await conflictedController(left: "base", right: "conflict")
        defer { controller.resetSession() }
        let conflict = try controller.nextConflict()
        let presentation = try XCTUnwrap(conflict.playlistPresentation)
        XCTAssertEqual(presentation.fields, [.label, .endAction])
        XCTAssertEqual(conflict.left?.related.independentMedia?.originalFilename, "A.bin")
        XCTAssertEqual(conflict.left?.related.tag?.name, "Common")
        let context = PlaylistContextPresentation(related: conflict.left?.related, publication: nil, itemTitle: "A")
        XCTAssertEqual(context.rows.map(\.key), ["Media:", "Playlist:"])
        XCTAssertEqual(context.rows.first?.value, "A.bin")
        try await captureConflict(controller, name: "binary-settings-conflict")
    }

    func testMissingTitleKeepsItemContext() throws {
        let nullInt = #"{"Int32":0,"Valid":false}"#
        let json = #"{"location":{"locationId":1,"bookNumber":\#(nullInt),"chapterNumber":\#(nullInt),"#
            + #""documentId":{"Int64":0,"Valid":false},"track":\#(nullInt),"issueTagNumber":0,"#
            + #""keySymbol":{"String":"jwb-142","Valid":true},"mepsLanguage":\#(nullInt),"locationType":3,"#
            + #""title":{"String":"","Valid":false}},"tag":{"tagId":1,"tagType":2,"name":"Example"}}"#
        let related = try JSONDecoder().decode(Related.self, from: Data(json.utf8))
        let context = PlaylistContextPresentation(related: related, publication: nil,
                                                  itemTitle: "October programme excerpt")
        XCTAssertEqual(context.rows.map(\.key), ["Title:", "Playlist:"])
        XCTAssertEqual(context.rows.first?.value, "October programme excerpt")
    }

    private func conflictedController(left: String, right: String) async throws -> MergerController {
        let controller = MergerController()
        let bundle = Bundle(for: Self.self)
        let leftURL = try XCTUnwrap(bundle.url(forResource: left, withExtension: "jwlibrary", subdirectory: "Fixtures"))
        let rightURL = try XCTUnwrap(bundle.url(forResource: right, withExtension: "jwlibrary",
                                              subdirectory: "Fixtures"))
        try await controller.importBackup(url: leftURL, side: .leftSide)
        try await controller.importBackup(url: rightURL, side: .rightSide)
        do {
            try await controller.merge(progress: MergeProgress())
            XCTFail("Expected meaningful settings conflict")
        } catch MergeError.mergeConflict { }
        return controller
    }

    private func captureConflict(_ controller: MergerController, name: String) async throws {
        let host = UIHostingController(rootView:
            MergeConflictResolutionView(mergerController: controller, cancelMerge: .constant(false)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 500_000_000)
        host.view.layoutIfNeeded()
        let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaylistValidation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(screenshot.pngData()).write(to: output.appendingPathComponent(name + ".png"))
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
