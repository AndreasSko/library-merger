import Foundation
import XCTest
@testable import LibraryMerger

final class BackupFileStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("backup-store-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingDocumentsDirectoryThrowsInsteadOfReturningInvalidPath() {
        XCTAssertThrowsError(try BackupFileStore(documentsDirectory: nil).newExportURL())
    }

    func testExportsAtSameTimeHaveUniqueNamesAndRetainPreviousFiles() throws {
        let root = try temporaryDirectory()
        let store = BackupFileStore(documentsDirectory: root)
        let now = Date(timeIntervalSince1970: 100)
        let first = try store.newExportURL(now: now)
        try Data("fictional first export".utf8).write(to: first)
        let second = try store.newExportURL(now: now)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent().path, root.path)
        XCTAssertEqual(second.pathExtension, "jwlibrary")
        XCTAssertEqual(try Data(contentsOf: first), Data("fictional first export".utf8))
    }

    @MainActor
    func testFailedImportPreservesOriginalBackupForRetry() async throws {
        let root = try temporaryDirectory()
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let selected = inbox.appendingPathComponent("invalid.jwlibrary")
        let bytes = Data("fictional invalid backup".utf8)
        try bytes.write(to: selected)
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let controller = MergerController(fileStore: BackupFileStore(documentsDirectory: root),
                                          fileLoader: BackupFileLoader(stagingRoot: staging))
        defer { controller.resetSession() }
        do {
            try await controller.importBackup(url: selected, side: .leftSide)
            XCTFail("Invalid backup should fail import")
        } catch {
            XCTAssertEqual(try Data(contentsOf: selected), bytes)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        }
    }

    @MainActor
    func testSuccessfulImportPreservesAllOriginalsAndCleansStaging() async throws {
        let root = try temporaryDirectory()
        let inbox = root.appendingPathComponent("Inbox")
        let staging = root.appendingPathComponent("staging")
        for directory in [inbox, staging] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "base",
            withExtension: "jwlibrary", subdirectory: "Fixtures"))
        let selected = inbox.appendingPathComponent("selected.jwlibrary")
        let pending = inbox.appendingPathComponent("pending.jwlibrary")
        try FileManager.default.copyItem(at: fixture, to: selected)
        try FileManager.default.copyItem(at: fixture, to: pending)
        let controller = MergerController(fileStore: BackupFileStore(documentsDirectory: root),
                                          fileLoader: BackupFileLoader(stagingRoot: staging))
        defer { controller.resetSession() }
        try await controller.importBackup(url: selected, side: .leftSide)
        XCTAssertNotNil(controller.dbWrapper.stats(MergeSide.leftSide.rawValue))
        XCTAssertEqual(try Data(contentsOf: selected), try Data(contentsOf: fixture))
        XCTAssertEqual(try Data(contentsOf: pending), try Data(contentsOf: fixture))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @MainActor
    func testOriginalReplacementAfterSnapshotSurvivesSuccessfulImport() async throws {
        let root = try temporaryDirectory()
        let inbox = root.appendingPathComponent("Inbox")
        let staging = root.appendingPathComponent("staging")
        for directory in [inbox, staging] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "base",
            withExtension: "jwlibrary", subdirectory: "Fixtures"))
        let selected = inbox.appendingPathComponent("selected.jwlibrary")
        try FileManager.default.copyItem(at: fixture, to: selected)
        let replacement = Data("fictional newer backup".utf8)
        let coordinator = ReplacingBackupCoordinator(replacement: replacement)
        let loader = BackupFileLoader(stagingRoot: staging, availability: { _ in .local },
                                      makeCoordinator: { coordinator })
        let controller = MergerController(fileStore: BackupFileStore(documentsDirectory: root),
                                          fileLoader: loader)
        defer { controller.resetSession() }
        try await controller.importBackup(url: selected, side: .leftSide)
        XCTAssertNotNil(controller.dbWrapper.stats(MergeSide.leftSide.rawValue))
        XCTAssertEqual(try Data(contentsOf: selected), replacement)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    func testShareItemAlwaysContainsAnImmutableURLAndUniqueIdentity() throws {
        let root = try temporaryDirectory()
        let url = try BackupFileStore(documentsDirectory: root).newExportURL()
        let first = BackupShareItem(url: url)
        let second = BackupShareItem(url: url)
        XCTAssertEqual(first.url, url)
        XCTAssertNotEqual(first.id, second.id)
    }
}

private final class ReplacingBackupCoordinator: BackupFileCoordinating {
    let replacement: Data

    init(replacement: Data) { self.replacement = replacement }

    func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        try accessor(url)
        // Simulate replacement after acquisition has copied the selected bytes,
        // before the controller imports that immutable snapshot.
        try replacement.write(to: url, options: .atomic)
    }

    func cancel() {}
}
