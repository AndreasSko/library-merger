//
//  MergerController.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//  Copyright © 2020 Andreas Skorczyk. All rights reserved.
//

import Foundation
import Gomobile
import Sentry

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
    var playlistPresentation: PlaylistConflictPresentation?
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

class MergerController: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var sessionID = UUID()
    @Published private(set) var conflictResolutionID: UUID?
    private var hasMergedBackup = false
    var dbWrapper: GomobileDatabaseWrapper
    var mergeConflicts: GomobileMergeConflictsWrapper
    var settings: MergeSettings

    init() {
        addBreadcrumb("MergerController.init")
        self.dbWrapper = GomobileDatabaseWrapper()
        self.dbWrapper.tempDir = getTempDir()
        self.mergeConflicts = GomobileMergeConflictsWrapper()
        self.mergeConflicts.initDBWrapper(dbWrapper)
        self.settings = MergeSettings(bookmarkResolver: .disabled,
                                      markingResolver: .disabled,
                                      noteResolver: .disabled,
                                      inputFieldResolver: .disabled)
    }

    deinit {
        // Imported media is needed across conflict retries and repeated exports.
        // The wrapper releases replaced inputs itself; close only at session end.
        try? dbWrapper.close()
    }

    @MainActor
    func resetSession() {
        guard !isBusy else { return }
        conflictResolutionID = nil
        hasMergedBackup = false
        sessionID = UUID()
        try? dbWrapper.close()
        dbWrapper = GomobileDatabaseWrapper()
        dbWrapper.tempDir = getTempDir()
        mergeConflicts = GomobileMergeConflictsWrapper()
        mergeConflicts.initDBWrapper(dbWrapper)
    }

    func importBackup(url: URL, side: MergeSide, sessionID: UUID? = nil) async throws {
        try await withOperation(sessionID: sessionID) {
            try await self.importBackupImpl(url: url, side: side)
            await MainActor.run { self.hasMergedBackup = false }
        }
    }

    func merge(reset: Bool = true, progress: MergeProgress, resolutionID: UUID? = nil,
               sessionID: UUID? = nil) async throws {
        try await withOperation(allowConflicts: true, resolutionID: resolutionID, sessionID: sessionID) {
            await MainActor.run {
                self.conflictResolutionID = nil
                self.hasMergedBackup = false
            }
            do {
                try await self.mergeImpl(reset: reset, progress: progress)
                await MainActor.run { self.hasMergedBackup = true }
            } catch MergeError.mergeConflict {
                await MainActor.run { self.conflictResolutionID = UUID() }
                throw MergeError.mergeConflict
            }
        }
    }

    private func withOperation<T>(allowConflicts: Bool = false, resolutionID: UUID? = nil,
                                  sessionID: UUID? = nil,
                                  _ operation: () async throws -> T) async throws -> T {
        try await MainActor.run {
            if let sessionID = sessionID, sessionID != self.sessionID {
                throw GeneralError.general(message: NSLocalizedString("Wait for the current operation to finish.",
                                                                      comment: "Busy merge session"))
            }
            if let resolutionID = resolutionID { try self.requireConflictResolution(resolutionID) }
            guard !self.isBusy && (allowConflicts || self.conflictResolutionID == nil) else {
                throw GeneralError.general(message: NSLocalizedString("Wait for the current operation to finish.",
                                                                      comment: "Busy merge session"))
            }
            self.isBusy = true
        }
        do {
            let result = try await operation()
            await MainActor.run { self.isBusy = false }
            return result
        } catch {
            await MainActor.run { self.isBusy = false }
            throw error
        }
    }

    @MainActor
    func solveConflict(_ key: String, side: MergeSide, resolutionID: UUID) throws {
        try requireConflictResolution(resolutionID)
        try mergeConflicts.solveConflict(key, side: side.rawValue)
    }

    private func importBackupImpl(url: URL, side: MergeSide) async throws {
        addBreadcrumb("importBackup from \(url.absoluteString) for side \(side.rawValue)")
        self.dbWrapper.skipPlaylists(false)

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        defer { cleanUpInbox() }

        do {
            try downloadFileIfNecessary(url: url)
        } catch {
            captureError(error, userInfo: [
                "url": url.absoluteString,
                "accessGranted": accessGranted,
                "fileExists": FileManager.default.fileExists(atPath: url.path),
                "isReadable": FileManager.default.isReadableFile(atPath: url.path),
                "bookmarkDataExists": (try? url.bookmarkData()) != nil
            ])

            throw error
        }

        do {
            try dbWrapper.importJWLBackup(url.path, side: side.rawValue)
        } catch {
            captureError(error, userInfo: [
                "url": url.absoluteString,
                "accessGranted": accessGranted,
                "fileExists": FileManager.default.fileExists(atPath: url.path),
                "isReadable": FileManager.default.isReadableFile(atPath: url.path),
                "bookmarkDataExists": (try? url.bookmarkData()) != nil
            ])

            throw error
        }
    }

    func downloadFileIfNecessary(url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            return
        }

        // First, try for iCloud files (ubiquitous items)
        if fileManager.isUbiquitousItem(at: url) {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        } else {
            // For third-party cloud providers, use NSFileCoordinator
            var error: NSError?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { _ in
            }

            if let error = error {
                throw error
            }
        }

        var wait = 0
        while true {
            if wait > 60 {
                throw GeneralError.timeout(message: "Failed to download \(url.lastPathComponent). "
                    + "Timeout after \(wait) seconds. Please try again.")
            }
            if fileManager.fileExists(atPath: url.path) {
                return
            }
            sleep(1)
            wait += 1
        }
    }

    private func exportBackupImpl() async throws -> String {
        addBreadcrumb("exportBackup")
        do {
            cleanUpMergedFiles()
            if !self.dbWrapper.dbIsLoaded("mergeSide") {
                throw MergeError.notInitialized(message: "There is no merged backup yet")
            }

            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let filename = "merged" + String(Int(NSDate().timeIntervalSince1970)) + ".jwlibrary"
            let path = dir?.appendingPathComponent(filename).path

            try dbWrapper.exportMerged(path)

            return path!
        } catch {
            SentrySDK.capture(error: error)
            throw error
        }
    }

    // cleanUpMergedFiles removes all files starting with `merged` from the documentDirectory,
    // as they are the result of older merges
    func cleanUpMergedFiles() {
        let fileManager = FileManager.default
        do {
            let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            let files = try fileManager.contentsOfDirectory(at: dir!.absoluteURL,
                                                   includingPropertiesForKeys: [.isRegularFileKey])
            for file in files where file.lastPathComponent.hasPrefix("merged") {
                try fileManager.removeItem(at: file)
                print("Cleaning up \(file.absoluteString)")
            }
        } catch {
            SentrySDK.capture(error: error)
            print("Error while trying to clean up old files")
        }
    }

    // cleanUpInbox removes all files inside the inbox
    func cleanUpInbox() {
        let fileManager = FileManager.default
        do {
            let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Inbox")
            let files = try fileManager.contentsOfDirectory(at: dir!.absoluteURL,
                                                   includingPropertiesForKeys: [.isRegularFileKey])
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                // Ignore error code 260 (file doesn't exist) as it's not an actual problem
                return
            }
            SentrySDK.capture(error: error)
        }
    }

    private func mergeImpl(reset: Bool, progress: MergeProgress) async throws {
        addBreadcrumb("merge")
        if !self.dbWrapper.dbIsLoaded(MergeSide.leftSide.rawValue)
           || !self.dbWrapper.dbIsLoaded(MergeSide.rightSide.rawValue) {
            throw MergeError.notInitialized(message: "At least one backup has not been imported yet")
        }
        if reset {
            mergeConflicts = GomobileMergeConflictsWrapper()
            mergeConflicts.initDBWrapper(dbWrapper)
        }

        dbWrapper.init_()

        do {
            await progress.update(status: "Merging Locations", percent: 14)
            try dbWrapper.mergeLocations()

            await progress.update(status: "Merging Bookmarks", percent: 28)
            try dbWrapper.mergeBookmarks(self.settings.bookmarkResolver.rawValue, mcw: self.mergeConflicts)

            await progress.update(status: "Merging InputFields", percent: 42)
            try dbWrapper.mergeInputFields(self.settings.inputFieldResolver.rawValue, mcw: self.mergeConflicts)

            await progress.update(status: "Merging Tags", percent: 56)
            try dbWrapper.mergeTags()

            await progress.update(status: "Merging Markings", percent: 70)
            try dbWrapper.mergeUserMarkAndBlockRange(self.settings.markingResolver.rawValue, mcw: self.mergeConflicts)

            await progress.update(status: "Merging Notes", percent: 84)
            try dbWrapper.mergeNotes(self.settings.noteResolver.rawValue, mcw: self.mergeConflicts)

            await progress.update(status: NSLocalizedString("Merging Playlists", comment: "Merge progress"),
                                  percent: 91)
            try dbWrapper.mergePlaylists("", mcw: self.mergeConflicts)

            await progress.update(status: "Merging TagMaps", percent: 98)
            try dbWrapper.mergeTagMaps()

            await progress.update(status: "Done", percent: 100)
        } catch {
            if error.localizedDescription.starts(with: "There were conflicts while trying to merge") {
                throw MergeError.mergeConflict
            }
            SentrySDK.capture(error: error)
            throw MergeError.error(message: error.localizedDescription)
        }
    }

}

extension MergerController {
    private func requireConflictResolution(_ resolutionID: UUID) throws {
        guard !isBusy, conflictResolutionID == resolutionID else {
            throw GeneralError.general(message: NSLocalizedString("Wait for the current operation to finish.",
                                                                  comment: "Busy merge session"))
        }
    }
}

extension MergerController {
    func exportBackup(sessionID: UUID? = nil) async throws -> String {
        try await withOperation(sessionID: sessionID) {
            try await MainActor.run {
                guard self.hasMergedBackup else {
                    throw MergeError.notInitialized(message: "There is no merged backup yet")
                }
            }
            return try await self.exportBackupImpl()
        }
    }
}

extension MergerController {
    @MainActor
    func cancelConflictResolution(_ resolutionID: UUID) {
        guard !isBusy, conflictResolutionID == resolutionID else { return }
        conflictResolutionID = nil
        mergeConflicts = GomobileMergeConflictsWrapper()
        mergeConflicts.initDBWrapper(dbWrapper)
    }
}

extension MergerController {
    func nextConflict(resolutionID: UUID? = nil) throws -> MergeConflict {
        if let resolutionID = resolutionID { try requireConflictResolution(resolutionID) }
        addBreadcrumb("nextConflict")
        do {
            let conflict = try self.mergeConflicts.nextConflict()
            let left = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                from: conflict.left.data(using: .utf8)!)
            let right = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                 from: conflict.right.data(using: .utf8)!)
            let presentation: PlaylistConflictPresentation?
            switch left.model {
            case .playlistItem, .playlistItemLocationMap, .playlistItemIndependentMediaMap:
                presentation = try PlaylistConflictPresentation(changedFieldsJSON: conflict.changedFields,
                                                               model: left.model)
                _ = try presentation?.rows(for: right.model)
            default:
                presentation = nil
            }
            return MergeConflict(key: conflict.key, left: left, right: right, playlistPresentation: presentation)
        } catch {
            if error.localizedDescription.starts(with: "There are no unsolved conflicts") {
                throw MergeError.noConflicts
            }
            SentrySDK.capture(error: error)
            throw error
        }
    }
}
