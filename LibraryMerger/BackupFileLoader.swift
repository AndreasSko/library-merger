import Foundation

enum ImportPhase {
    case downloading
    case opening
    case importing
}

/// Makes a selected backup readable for Go. It waits for as long as the
/// download from iCloud or another provider takes, and copies the backup into a
/// private folder, because the selected URL is only safe to read inside a
/// coordinated read.
final class BackupFileLoader {
    struct StagedBackup {
        let url: URL

        func remove() {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "BackupFileLoader", qos: .userInitiated)
    private let stagingRoot: URL

    init(stagingRoot: URL = FileManager.default.temporaryDirectory) {
        self.stagingRoot = stagingRoot
    }

    func load(_ source: URL, phase: @escaping @MainActor (ImportPhase) -> Void) async throws -> StagedBackup {
        if let status = try iCloudState(source)?.ubiquitousItemDownloadingStatus, status != .current {
            await phase(.downloading)
            try await waitForICloudDownload(source)
        }

        // Other providers download the file as part of the coordinated read.
        await phase(.opening)
        do {
            return try await copy(source)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func waitForICloudDownload(_ source: URL) async throws {
        try fileManager.startDownloadingUbiquitousItem(at: source)
        let started = ProcessInfo.processInfo.systemUptime
        while true {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let state = try iCloudState(source),
                  let status = state.ubiquitousItemDownloadingStatus,
                  status != .current else { return }

            // An older copy is on the device, but iCloud isn't fetching the
            // newer one (for example when offline): use the older copy.
            if status == .downloaded && state.ubiquitousItemIsDownloading != true {
                return
            }
            // The error can be left over from an earlier attempt, so give the
            // new download a moment before trusting it.
            if let error = state.ubiquitousItemDownloadingError,
               ProcessInfo.processInfo.systemUptime - started > 5 {
                throw error
            }
        }
    }

    private func iCloudState(_ url: URL) throws -> URLResourceValues? {
        guard fileManager.isUbiquitousItem(at: url) else { return nil }

        var url = url
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey,
                                                .ubiquitousItemIsDownloadingKey,
                                                .ubiquitousItemDownloadingErrorKey])
    }

    private func copy(_ source: URL) async throws -> StagedBackup {
        let directory = stagingRoot.appendingPathComponent("backup-import-" + UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("backup.jwlibrary")
        // cancel() is meant to be called from another thread while a read waits.
        nonisolated(unsafe) let coordinator = NSFileCoordinator(filePresenter: nil)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let fileManager = FileManager.default
                    do {
                        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                        var coordinationError: NSError?
                        var copyError: Error?
                        coordinator.coordinate(readingItemAt: source,
                                               options: [.withoutChanges, .resolvesSymbolicLink],
                                               error: &coordinationError) { url in
                            do {
                                try fileManager.copyItem(at: url, to: destination)
                            } catch {
                                copyError = error
                            }
                        }
                        if let error = copyError ?? coordinationError {
                            throw error
                        }
                        continuation.resume(returning: StagedBackup(url: destination))
                    } catch {
                        try? fileManager.removeItem(at: directory)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}
