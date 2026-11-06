import XCTest
@testable import LibraryMerger

final class BackupFileLoaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("loader-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("staging"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var stagingContents: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("staging").path)) ?? []
    }

    func testLoadCopiesBackupAndRemoveCleansUp() async throws {
        let source = root.appendingPathComponent("selected.jwlibrary")
        try Data("backup".utf8).write(to: source)
        var phases: [ImportPhase] = []

        let staged = try await BackupFileLoader(stagingRoot: root.appendingPathComponent("staging"))
            .load(source) { phases.append($0) }

        XCTAssertEqual(phases, [.opening])
        XCTAssertNotEqual(staged.url, source)
        XCTAssertEqual(try Data(contentsOf: staged.url), Data("backup".utf8))
        staged.remove()
        XCTAssertEqual(stagingContents, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testLoadOfMissingFileThrowsAndLeavesNothingBehind() async {
        let source = root.appendingPathComponent("missing.jwlibrary")

        do {
            _ = try await BackupFileLoader(stagingRoot: root.appendingPathComponent("staging"))
                .load(source) { _ in }
            XCTFail("Expected an error")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        XCTAssertEqual(stagingContents, [])
    }

    func testCancelledLoadThrowsCancellationError() async throws {
        let source = root.appendingPathComponent("selected.jwlibrary")
        try Data("backup".utf8).write(to: source)
        let loader = BackupFileLoader(stagingRoot: root.appendingPathComponent("staging"))

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(source) { _ in }
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(stagingContents, [])
    }

    func testInboxCleanupKeepsFreshAndRemovesImportedBackups() throws {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let inbox = documents.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let fresh = inbox.appendingPathComponent("fresh-\(UUID().uuidString).jwlibrary")
        try Data("backup".utf8).write(to: fresh)
        defer { try? FileManager.default.removeItem(at: fresh) }
        let controller = MergerController()

        controller.cleanUpInbox()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))

        controller.removeFromInbox(root.appendingPathComponent("elsewhere.jwlibrary"))
        controller.removeFromInbox(fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
    }
}
