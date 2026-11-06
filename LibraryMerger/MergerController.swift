//
//  MergerController.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//  Copyright © 2020 Andreas Skorczyk. All rights reserved.
//

import Foundation
import Gomobile
import UIKit

enum MergeSide: String {
    case leftSide
    case rightSide
}

struct ModelRelatedTuple: Decodable {
    let model: Model
    let related: Related
    let sourceURL: String?
}

struct MergeConflict {
    let key: String
    let left: ModelRelatedTuple?
    let right: ModelRelatedTuple?
    var changedFields: [PlaylistChangedField] = []
    var thumbnail: UIImage?
}

enum ConflictSolver: String {
    case disabled = ""
    case chooseLeft = "chooseLeft"
    case chooseRight = "chooseRight"
    case chooseNewest = "chooseNewest"
}

struct MergeSettings {
    var bookmarkResolver: ConflictSolver
    var markingResolver: ConflictSolver
    var noteResolver: ConflictSolver
    var inputFieldResolver: ConflictSolver
    var playlistResolver: ConflictSolver
}

class MergeProgress: ObservableObject {
    @Published var status: String = ""
    @Published var percent: Float = 0

    @MainActor
    func update(status: String, percent: Float) {
        self.status = status
        self.percent = percent
    }
}

enum MergeError: Error {
    case notInitialized(message: String)
    case mergeConflict
    case noConflicts
    case error(message: String)
}

extension MergeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized(let message):
            return message
        case .error(let message):
            return message
        default:
            return ""
        }
    }
}

class MergerController: ObservableObject {
    var dbWrapper: GomobileDatabaseWrapper
    var mergeConflicts: GomobileMergeConflictsWrapper
    @Published var settings: MergeSettings
    var publicationCacheDir = LibraryMerger.publicationCacheDir

    private var solvedConflicts = 0

    init() {
        addBreadcrumb("MergerController.init")
        self.dbWrapper = GomobileDatabaseWrapper()
        self.dbWrapper.tempDir = getTempDir()
        self.mergeConflicts = GomobileMergeConflictsWrapper()
        self.mergeConflicts.initDBWrapper(dbWrapper)
        self.settings = MergeSettings(bookmarkResolver: .disabled,
                                      markingResolver: .disabled,
                                      noteResolver: .disabled,
                                      inputFieldResolver: .disabled,
                                      playlistResolver: .disabled)
        cleanUpInbox()
    }

    func importBackup(url: URL, side: MergeSide,
                      phase: @escaping @MainActor (ImportPhase) -> Void = { _ in }) async throws {
        addBreadcrumb("import.begin", data: ["side": side.rawValue])
        self.dbWrapper.skipUnsupportedPlaylists(true)

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        defer { removeFromInbox(url) }
        let started = ProcessInfo.processInfo.systemUptime
        var details: [String: Any] = [
            "access_granted": accessGranted,
            "icloud": FileManager.default.isUbiquitousItem(at: url)
        ]

        let staged: BackupFileLoader.StagedBackup
        do {
            staged = try await BackupFileLoader().load(url, phase: phase)
        } catch {
            details["seconds"] = ProcessInfo.processInfo.systemUptime - started
            addBreadcrumb(Diagnostics.isCancellation(error) ? "import.cancelled" : "import.failed",
                          data: ["stage": "file"])
            captureError(error, operation: "import", stage: "file", side: side, details: details)
            throw error
        }
        defer { staged.remove() }
        let fileSeconds = ProcessInfo.processInfo.systemUptime - started
        details["file_seconds"] = fileSeconds
        addBreadcrumb("import.file-ready", data: ["seconds": fileSeconds])
        try Task.checkCancellation()

        await phase(.importing)
        do {
            try dbWrapper.importJWLBackup(staged.url.path, side: side.rawValue)
            addBreadcrumb("import.complete", data: ["seconds": ProcessInfo.processInfo.systemUptime - started])
        } catch {
            addBreadcrumb("import.failed", data: ["stage": "go-import"])
            captureError(error, operation: "import", stage: "go-import", side: side, details: details)
            throw error
        }
    }

    func exportBackup() async throws -> String {
        addBreadcrumb("export.begin")
        do {
            cleanUpMergedFiles()
            if !self.dbWrapper.dbIsLoaded("mergeSide") {
                throw MergeError.notInitialized(message: "There is no merged backup yet")
            }

            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let filename = "merged" + String(Int(NSDate().timeIntervalSince1970)) + ".jwlibrary"
            let path = dir?.appendingPathComponent(filename).path

            try dbWrapper.exportMerged(path)

            addBreadcrumb("export.complete")
            return path!
        } catch {
            captureError(error, operation: "export", stage: "go-export")
            throw error
        }
    }

    // cleanUpMergedFiles removes all files starting with `merged` from the documentDirectory,
    // as they are the result of older merges
    func cleanUpMergedFiles() {
        let fm = FileManager.default
        do {
            let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            let files = try fm.contentsOfDirectory(at: dir!.absoluteURL,
                                                   includingPropertiesForKeys: [.isRegularFileKey])
            for file in files where file.lastPathComponent.hasPrefix("merged") {
                try fm.removeItem(at: file)
                print("Cleaning up \(file.absoluteString)")
            }
        } catch {
            captureError(error, operation: "cleanup", stage: "exports")
        }
    }

    // removeFromInbox removes a backup that was shared into the app once it's imported.
    // Only this file is removed: another backup may have been shared in the meantime.
    func removeFromInbox(_ url: URL) {
        guard let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Inbox"),
              url.deletingLastPathComponent().resolvingSymlinksInPath().path
                == inbox.resolvingSymlinksInPath().path else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // cleanUpInbox removes backups that were shared into the app more than a day ago
    // but never imported. Newer ones may be about to be imported.
    func cleanUpInbox() {
        let fm = FileManager.default
        do {
            let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox")
            let files = try fm.contentsOfDirectory(at: dir!.absoluteURL,
                                                   includingPropertiesForKeys: [.addedToDirectoryDateKey])
            let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            for file in files {
                let added = try file.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
                if let added, added < dayAgo {
                    try fm.removeItem(at: file)
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                // Ignore error code 260 (file doesn't exist) as it's not an actual problem
                return
            }
            captureError(error, operation: "cleanup", stage: "inbox")
        }
    }

    func merge(reset: Bool = true, progress: MergeProgress) async throws {
        addBreadcrumb("merge.begin")
        if !self.dbWrapper.dbIsLoaded(MergeSide.leftSide.rawValue)
           || !self.dbWrapper.dbIsLoaded(MergeSide.rightSide.rawValue) {
            throw MergeError.notInitialized(message: "At least one backup has not been imported yet")
        }
        if reset {
            mergeConflicts = GomobileMergeConflictsWrapper()
            mergeConflicts.initDBWrapper(dbWrapper)
        }

        var stage = "init"
        func report(_ status: String, _ percent: Float, _ nextStage: String) async {
            stage = nextStage
            addBreadcrumb("merge.stage", data: ["stage": nextStage])
            await progress.update(status: status, percent: percent)
        }

        do {
            try dbWrapper.init_()

            await report("Merging Locations", 14, "locations")
            try dbWrapper.mergeLocations()

            await report("Merging Bookmarks", 28, "bookmarks")
            try dbWrapper.mergeBookmarks(self.settings.bookmarkResolver.rawValue, mcw: self.mergeConflicts)

            await report("Merging InputFields", 42, "input-fields")
            try dbWrapper.mergeInputFields(self.settings.inputFieldResolver.rawValue, mcw: self.mergeConflicts)

            await report("Merging Tags", 56, "tags")
            try dbWrapper.mergeTags()

            await report("Merging Markings", 70, "markings")
            try dbWrapper.mergeUserMarkAndBlockRange(self.settings.markingResolver.rawValue, mcw: self.mergeConflicts)

            await report("Merging Notes", 84, "notes")
            try dbWrapper.mergeNotes(self.settings.noteResolver.rawValue, mcw: self.mergeConflicts)

            await report("Merging Playlists", 91, "playlists")
            try dbWrapper.mergePlaylists(self.settings.playlistResolver.rawValue, mcw: self.mergeConflicts)

            await report("Merging TagMaps", 98, "tag-maps")
            try dbWrapper.mergeTagMaps()

            await progress.update(status: "Done", percent: 100)
            addBreadcrumb("merge.complete")
        } catch {
            if error.localizedDescription.starts(with: "There were conflicts while trying to merge") {
                addBreadcrumb("merge.conflicts", data: ["stage": stage])
                throw MergeError.mergeConflict
            }
            captureError(error, operation: "merge", stage: stage)
            throw MergeError.error(message: error.localizedDescription)
        }
    }

    func nextConflict() throws -> MergeConflict {
        addBreadcrumb("nextConflict")
        do {
            let conflict = try self.mergeConflicts.nextConflict()
            let left = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                from: conflict.left.data(using: .utf8)!)
            let right = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                 from: conflict.right.data(using: .utf8)!)
            let changedFields = try JSONDecoder().decode([PlaylistChangedField].self,
                                                         from: Data(conflict.changedFields.utf8))
            return MergeConflict(key: conflict.key, left: left, right: right, changedFields: changedFields,
                                 thumbnail: playlistThumbnail(left.model))
        } catch {
            if error.localizedDescription.starts(with: "There are no unsolved conflicts") {
                throw MergeError.noConflicts
            }
            captureError(error, operation: "conflict", stage: "next")
            throw error
        }
    }

    // markingSnippets returns the paragraphs that the marking on one side of a conflict covers.
    // The first lookup of a publication downloads it from jw.org, so this runs in the background,
    // and listener is told the progress. If jw.org has no text of the publication, it returns no
    // paragraphs. It throws if the text could not be loaded, for example when offline.
    func markingSnippets(key: String, side: MergeSide, listener: DownloadListener? = nil) async throws
        -> [MarkingSnippet] {
        do {
            var lookupError: NSError?
            let json = mergeConflicts.markingSnippets(key, side: side.rawValue, cacheDir: publicationCacheDir.path,
                                                      listener: listener, error: &lookupError)
            if let lookupError = lookupError {
                throw lookupError
            }
            return try JSONDecoder().decode([MarkingSnippet].self, from: Data(json.utf8))
        } catch {
            addBreadcrumb("marking-snippets.failed", data: ["error": error.localizedDescription])
            throw error
        }
    }

    // Only item conflicts refer to the item IDs of the imported backup, which
    // the thumbnail lookup needs. Items without a thumbnail show none.
    private func playlistThumbnail(_ model: Model) -> UIImage? {
        guard case .playlistItem(let item) = model, item.thumbnailFilePath.valid,
              let data = try? dbWrapper.playlistThumbnail(MergeSide.leftSide.rawValue,
                                                          playlistItemID: item.playlistItemId) else {
            return nil
        }
        return UIImage(data: data)
    }
}

// DownloadListener reports on the main thread how many bytes of a publication are downloaded,
// out of total, which is -1 if unknown
final class DownloadListener: NSObject, GomobileDownloadListenerProtocol {
    private let report: (Int64, Int64) -> Void

    init(report: @escaping (Int64, Int64) -> Void) {
        self.report = report
    }

    func progress(_ downloaded: Int64, total: Int64) {
        DispatchQueue.main.async {
            self.report(downloaded, total)
        }
    }
}

func getTempDir() -> String {
    do {
        let temporaryDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return temporaryDirectory.path
    } catch {
        return FileManager.default.temporaryDirectory.path
    }
}
