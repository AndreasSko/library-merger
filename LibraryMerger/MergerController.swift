//
//  MergerController.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//  Copyright © 2020 Andreas Skorczyk. All rights reserved.
//

import Foundation
import Gomobile

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
        do {
            try mergeConflicts.solveConflict(key, side: side.rawValue)
            addBreadcrumb("conflict.resolved", data: ["side": side.rawValue])
        } catch {
            captureError(error, operation: "conflict", stage: "resolve", side: side)
            throw error
        }
    }

    private func importBackupImpl(url: URL, side: MergeSide) async throws {
        addBreadcrumb("import.begin", data: ["side": side.rawValue])
        dbWrapper.skipPlaylists(false)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        defer { cleanUpInbox() }
        let started = ProcessInfo.processInfo.systemUptime
        var stage = "file-acquisition"
        var details: [String: Any] = ["access_granted": accessGranted]
        do {
            let staged = try await BackupFileLoader().load(url)
            defer { staged.cleanup() }
            details["provider"] = staged.provider.rawValue
            details["acquisition_seconds"] = staged.elapsedSeconds
            stage = "go-import"
            addBreadcrumb("import.file-ready", data: details)
            try Task.checkCancellation()
            try dbWrapper.importJWLBackup(staged.url.path, side: side.rawValue)
            addBreadcrumb("import.complete", data: [
                "side": side.rawValue, "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started
            ])
        } catch {
            if let loadError = error as? BackupFileLoader.LoadError {
                stage = loadError.stage
                details["provider"] = loadError.provider.rawValue
                details["acquisition_seconds"] = loadError.elapsedSeconds
            }
            details["elapsed_seconds"] = ProcessInfo.processInfo.systemUptime - started
            let cancelled = MergerDiagnostics.isCancellation(error)
            addBreadcrumb(cancelled ? "import.cancelled" : "import.failed", data: ["stage": stage])
            captureError(error, operation: "import", stage: stage, side: side, details: details)
            throw error
        }
    }

    private func exportBackupImpl() async throws -> String {
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
            captureError(error, operation: "cleanup", stage: "exports")
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
            captureError(error, operation: "cleanup", stage: "inbox")
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

        var stage = "locations"
        do {
            await reportMergeStage(progress, status: "Merging Locations", percent: 14)
            try dbWrapper.mergeLocations()

            stage = "bookmarks"
            await reportMergeStage(progress, status: "Merging Bookmarks", percent: 28)
            try dbWrapper.mergeBookmarks(self.settings.bookmarkResolver.rawValue, mcw: self.mergeConflicts)

            stage = "input-fields"
            await reportMergeStage(progress, status: "Merging InputFields", percent: 42)
            try dbWrapper.mergeInputFields(self.settings.inputFieldResolver.rawValue, mcw: self.mergeConflicts)

            stage = "tags"
            await reportMergeStage(progress, status: "Merging Tags", percent: 56)
            try dbWrapper.mergeTags()

            stage = "markings"
            await reportMergeStage(progress, status: "Merging Markings", percent: 70)
            try dbWrapper.mergeUserMarkAndBlockRange(self.settings.markingResolver.rawValue, mcw: self.mergeConflicts)

            stage = "notes"
            await reportMergeStage(progress, status: "Merging Notes", percent: 84)
            try dbWrapper.mergeNotes(self.settings.noteResolver.rawValue, mcw: self.mergeConflicts)

            stage = "playlists"
            await reportMergeStage(progress, status: NSLocalizedString("Merging Playlists", comment: "Merge progress"),
                                  percent: 91)
            try dbWrapper.mergePlaylists("", mcw: self.mergeConflicts)

            stage = "tag-maps"
            await reportMergeStage(progress, status: "Merging TagMaps", percent: 98)
            try dbWrapper.mergeTagMaps()

            await reportMergeStage(progress, status: "Done", percent: 100)
            addBreadcrumb("merge.complete")
        } catch {
            if error.localizedDescription.starts(with: "There were conflicts while trying to merge") {
                throw MergeError.mergeConflict
            }
            captureError(error, operation: "merge", stage: stage)
            throw MergeError.error(message: error.localizedDescription)
        }
    }

    private func reportMergeStage(_ progress: MergeProgress, status: String, percent: Float) async {
        addBreadcrumb("merge.stage", data: ["status": status])
        await progress.update(status: status, percent: percent)
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
            captureError(error, operation: "conflict", stage: "decode-next")
            throw error
        }
    }
}
