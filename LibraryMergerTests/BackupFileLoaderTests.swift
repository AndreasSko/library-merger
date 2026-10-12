import XCTest
@testable import LibraryMerger

final class BackupFileLoaderTests: XCTestCase {
    func testProductionCoordinatorCopiesSymbolicLinkTargetIntoStableSnapshot() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let manager = FileManager.default
        let target = sandbox.root.appendingPathComponent("target.jwlibrary")
        let selected = sandbox.root.appendingPathComponent("selected.jwlibrary")
        let original = Data("original backup".utf8)
        let updated = Data("updated backup".utf8)
        try original.write(to: target)
        try manager.createSymbolicLink(at: selected, withDestinationURL: target)
        let loader = BackupFileLoader(stagingRoot: sandbox.staging, availability: { _ in .local })

        let staged = try await loader.load(selected)
        defer { staged.cleanup() }
        try updated.write(to: target)

        let values = try staged.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        XCTAssertEqual(values.isRegularFile, true)
        XCTAssertEqual(values.isSymbolicLink, false)
        XCTAssertEqual(try Data(contentsOf: staged.url), original)
        staged.cleanup()
        XCTAssertFalse(manager.fileExists(atPath: staged.url.path))
        XCTAssertEqual(try selected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try Data(contentsOf: target), updated)
        XCTAssertEqual(try Data(contentsOf: selected), updated)
    }

    func testCopiesCoordinatedURLAndKeepsSourceAfterCleanup() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let selected = sandbox.root.appendingPathComponent("selected.jwlibrary")
        let actual = sandbox.root.appendingPathComponent("actual.jwlibrary")
        try Data("coordinated bytes".utf8).write(to: actual)
        let coordinator = TestCoordinator(actualURL: actual)
        let loader = BackupFileLoader(stagingRoot: sandbox.staging,
                                      availability: { _ in .local },
                                      makeCoordinator: { coordinator })

        let staged = try await loader.load(selected)

        XCTAssertEqual(try Data(contentsOf: staged.url), Data("coordinated bytes".utf8))
        XCTAssertFalse(coordinator.wasOnMainThread)
        XCTAssertNotEqual(staged.url, actual)
        XCTAssertEqual(staged.provider, .local)
        staged.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: actual.path))
    }

    func testExistingICloudPlaceholderWaitsUntilCurrent() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let source = sandbox.root.appendingPathComponent("placeholder.jwlibrary")
        try Data("backup".utf8).write(to: source)
        let state = ClockState()
        let loader = BackupFileLoader(stagingRoot: sandbox.staging,
                                      availability: { _ in
                                          state.time < 1 ? .iCloud(.notDownloaded) : .iCloud(.current)
                                      },
                                      startDownload: { _ in state.downloadStarted = true },
                                      makeCoordinator: { TestCoordinator(actualURL: source) },
                                      now: { state.time }, pause: { state.time += 1 })

        let staged = try await loader.load(source)
        defer { staged.cleanup() }

        XCTAssertTrue(state.downloadStarted)
        XCTAssertEqual(staged.provider, .iCloud)
        XCTAssertEqual(staged.elapsedSeconds, 1)
    }

    func testStaleDownloadedBackupIsUpdatedBeforeCoordinatedCopy() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let source = sandbox.root.appendingPathComponent("stale.jwlibrary")
        try Data("old backup".utf8).write(to: source)
        let state = ClockState()
        let coordinator = TestCoordinator(actualURL: source)
        coordinator.beforeAccessor = {
            XCTAssertEqual(state.time, 1, "Coordination must wait for the current cloud version")
        }
        let loader = BackupFileLoader(stagingRoot: sandbox.staging,
                                      availability: { _ in
                                          state.time < 1 ? .iCloud(.downloaded) : .iCloud(.current)
                                      },
                                      startDownload: { _ in state.downloadStarted = true },
                                      makeCoordinator: { coordinator }, now: { state.time }, pause: {
                                          try Data("current backup".utf8).write(to: source)
                                          state.time += 1
                                      })

        let staged = try await loader.load(source)
        defer { staged.cleanup() }

        XCTAssertTrue(state.downloadStarted)
        XCTAssertEqual(staged.provider, .iCloud)
        XCTAssertEqual(staged.elapsedSeconds, 1)
        XCTAssertEqual(try Data(contentsOf: staged.url), Data("current backup".utf8))
        XCTAssertNotEqual(staged.url, source)
    }

    func testUnavailableICloudFileTimesOutWithoutStaging() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let state = ClockState()
        let loader = BackupFileLoader(stagingRoot: sandbox.staging, timeout: 2,
                                      availability: { _ in .iCloud(nil) }, startDownload: { _ in },
                                      now: { state.time }, pause: { state.time += 1 })
        do {
            _ = try await loader.load(sandbox.root.appendingPathComponent("missing.jwlibrary"))
            XCTFail("Expected download timeout")
        } catch let error as BackupFileLoader.LoadError {
            XCTAssertEqual(error.provider, .iCloud)
            XCTAssertEqual(error.stage, "download")
            XCTAssertEqual(error.elapsedSeconds, 2)
            XCTAssertTrue(error.localizedDescription.contains("could not be downloaded"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.staging.path), [])
    }

    func testPollingCancellationDoesNotBecomeAnImportFailure() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let sleeping = expectation(description: "Waiting for cloud download")
        let loader = BackupFileLoader(stagingRoot: sandbox.staging,
                                      availability: { _ in .iCloud(nil) }, startDownload: { _ in },
                                      pause: {
                                          sleeping.fulfill()
                                          try await Task.sleep(nanoseconds: 30_000_000_000)
                                      })
        let task = Task { try await loader.load(sandbox.root.appendingPathComponent("missing.jwlibrary")) }
        await fulfillment(of: [sleeping], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation is intentionally not wrapped as a reportable LoadError.
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.staging.path), [])
    }

    func testCoordinatedReadCancellationCleansPrivateDirectory() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let source = sandbox.root.appendingPathComponent("source.jwlibrary")
        try Data("backup".utf8).write(to: source)
        let entered = expectation(description: "Coordinator entered")
        let coordinator = TestCoordinator(actualURL: source)
        coordinator.beforeAccessor = {
            entered.fulfill()
            coordinator.cancelSignal.wait()
        }
        let loader = BackupFileLoader(stagingRoot: sandbox.staging, availability: { _ in .local },
                                      makeCoordinator: { coordinator })
        let task = Task { try await loader.load(source) }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.staging.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReadFailurePreservesCauseAndRemovesStaging() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let source = sandbox.root.appendingPathComponent("missing.jwlibrary")
        let loader = BackupFileLoader(stagingRoot: sandbox.staging, availability: { _ in .fileProvider },
                                      makeCoordinator: { TestCoordinator(actualURL: source) })
        do {
            _ = try await loader.load(source)
            XCTFail("Expected copy failure")
        } catch let error as BackupFileLoader.LoadError {
            XCTAssertEqual(error.stage, "coordinated-copy")
            XCTAssertEqual(error.provider, .fileProvider)
            XCTAssertEqual((error.underlying as NSError).domain, NSCocoaErrorDomain)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.staging.path), [])
    }
}

private final class TestCoordinator: BackupFileCoordinating {
    let actualURL: URL
    let cancelSignal = DispatchSemaphore(value: 0)
    var beforeAccessor: (() -> Void)?
    var wasOnMainThread = true

    init(actualURL: URL) { self.actualURL = actualURL }

    func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        wasOnMainThread = Thread.isMainThread
        beforeAccessor?()
        try accessor(actualURL)
    }

    func cancel() { cancelSignal.signal() }
}

private final class ClockState {
    var time: TimeInterval = 0
    var downloadStarted = false
}

private struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var staging: URL { root.appendingPathComponent("staging", isDirectory: true) }

    init() throws {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
