import Foundation

/// Coordinates and snapshots a selected backup before Go opens it. The caller
/// owns security-scoped access until this operation and the import finish.
final class BackupFileLoader {
    enum Provider: String {
        case local
        case iCloud
        case fileProvider
        case unknown
    }

    enum Availability {
        case local
        case iCloud(URLUbiquitousItemDownloadingStatus?)
        case fileProvider
        case unknown

        var isCurrentICloudCopy: Bool {
            if case .iCloud(let status) = self { return status == .current }
            return false
        }
    }

    struct LoadError: LocalizedError {
        let underlying: Error
        let provider: Provider
        let stage: String
        let elapsedSeconds: TimeInterval

        var errorDescription: String? { underlying.localizedDescription }
    }

    final class StagedBackupFile {
        let url: URL
        let provider: Provider
        let elapsedSeconds: TimeInterval
        private let directory: URL
        private let fileManager: FileManager

        fileprivate init(url: URL, directory: URL, provider: Provider,
                         elapsedSeconds: TimeInterval, fileManager: FileManager) {
            self.url = url
            self.directory = directory
            self.provider = provider
            self.elapsedSeconds = elapsedSeconds
            self.fileManager = fileManager
        }

        func cleanup() { try? fileManager.removeItem(at: directory) }
        deinit { cleanup() }
    }

    private let queue = DispatchQueue(label: "library-merger.backup-file-loader", qos: .utility)
    private let fileManager: FileManager
    private let stagingRoot: URL
    private let availability: (URL) throws -> Availability
    private let startDownload: (URL) throws -> Void
    private let makeCoordinator: () -> BackupFileCoordinating
    private let now: () -> TimeInterval
    private let pause: () async throws -> Void
    private let timeout: TimeInterval

    init(fileManager: FileManager = .default, stagingRoot: URL? = nil,
         timeout: TimeInterval = 60,
         availability: ((URL) throws -> Availability)? = nil,
         startDownload: ((URL) throws -> Void)? = nil,
         makeCoordinator: @escaping () -> BackupFileCoordinating = { BackupReadCoordinator() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         pause: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 250_000_000) }) {
        self.fileManager = fileManager
        self.stagingRoot = stagingRoot ?? fileManager.temporaryDirectory
        self.timeout = timeout
        self.makeCoordinator = makeCoordinator
        self.now = now
        self.pause = pause
        self.startDownload = startDownload ?? { try fileManager.startDownloadingUbiquitousItem(at: $0) }
        self.availability = availability ?? { url in
            if fileManager.isUbiquitousItem(at: url) {
                var refreshedURL = url
                refreshedURL.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
                let values = try refreshedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                return .iCloud(values.ubiquitousItemDownloadingStatus)
            }
            // This path hint is best-effort metadata, never exported verbatim.
            // Unrecognized providers and local selections remain unknown.
            return url.path.contains("/File Provider Storage/") ? .fileProvider : .unknown
        }
    }

    func load(_ source: URL) async throws -> StagedBackupFile {
        let started = now()
        var provider = Provider.unknown
        var stage = "availability"
        do {
            try Task.checkCancellation()
            let state = try await offMain { try self.availability(source) }
            switch state {
            case .iCloud: provider = .iCloud
            case .fileProvider: provider = .fileProvider
            case .local: provider = .local
            case .unknown: provider = .unknown
            }
            if provider == .iCloud && !state.isCurrentICloudCopy {
                stage = "download"
                try await waitForDownload(source, started: started)
            }
            stage = "coordinated-copy"
            return try await stageBackup(source, provider: provider, started: started)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LoadError(underlying: error, provider: provider, stage: stage,
                            elapsedSeconds: now() - started)
        }
    }

    private func waitForDownload(_ source: URL, started: TimeInterval) async throws {
        try await offMain { try self.startDownload(source) }
        var state = Availability.iCloud(nil)
        while !state.isCurrentICloudCopy {
            try Task.checkCancellation()
            guard now() - started < timeout else {
                throw GeneralError.timeout(message: "The backup could not be downloaded within 60 seconds. "
                    + "Please check your connection and try again.")
            }
            try await pause()
            state = try await offMain { try self.availability(source) }
        }
    }

    private func stageBackup(_ source: URL, provider: Provider,
                             started: TimeInterval) async throws -> StagedBackupFile {
        let directory = stagingRoot.appendingPathComponent("backup-import-" + UUID().uuidString,
                                                           isDirectory: true)
        let coordinator = makeCoordinator()
        let operation = BackupReadOperation(coordinator: coordinator)
        let staged = try await withTaskCancellationHandler(operation: {
            try await offMain {
                try self.copyBackup(source, directory: directory, provider: provider,
                                    started: started, operation: operation)
            }
        }, onCancel: { operation.cancel() })
        do {
            try Task.checkCancellation()
            return staged
        } catch {
            staged.cleanup()
            throw error
        }
    }

    private func copyBackup(_ source: URL, directory: URL, provider: Provider,
                            started: TimeInterval, operation: BackupReadOperation) throws -> StagedBackupFile {
        do {
            try operation.checkCancellation()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("backup.jwlibrary")
            try operation.read(source) { coordinatedURL in
                try operation.checkCancellation()
                try fileManager.copyItem(at: coordinatedURL, to: destination)
                try operation.checkCancellation()
            }
            try operation.checkCancellation()
            // A coordinator must either invoke the accessor or throw.
            guard fileManager.isReadableFile(atPath: destination.path) else {
                throw GeneralError.general(message: "The backup could not be read. Please try again.")
            }
            return StagedBackupFile(url: destination, directory: directory, provider: provider,
                                    elapsedSeconds: now() - started, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: directory)
            // Coordination errors produced by cancel() represent user cancellation.
            try operation.checkCancellation()
            throw error
        }
    }

    private func offMain<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

protocol BackupFileCoordinating: AnyObject {
    func read(_ url: URL, accessor: (URL) throws -> Void) throws
    func cancel()
}

private final class BackupReadCoordinator: BackupFileCoordinating {
    private let coordinator = NSFileCoordinator(filePresenter: nil)

    func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var readError: Error?
        let options: NSFileCoordinator.ReadingOptions = [.withoutChanges, .resolvesSymbolicLink]
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { actualURL in
            do {
                try accessor(actualURL)
            } catch {
                readError = error
            }
        }
        if let readError { throw readError }
        if let coordinationError { throw coordinationError }
    }

    func cancel() { coordinator.cancel() }
}

/// Cancellation does not resume early: an in-flight synchronous copy finishes
/// before its private staging directory is removed and the continuation resumes.
private final class BackupReadOperation {
    private let lock = NSLock()
    private var cancelled = false
    private let coordinator: BackupFileCoordinating

    init(coordinator: BackupFileCoordinating) { self.coordinator = coordinator }

    func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        try coordinator.read(url, accessor: accessor)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        coordinator.cancel()
    }

    func checkCancellation() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
}
