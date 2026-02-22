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
}

struct MergeConflict {
    let key: String
    let left: ModelRelatedTuple?
    let right: ModelRelatedTuple?
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

enum GeneralError: Error {
    case general(message: String)
    case timeout(message: String)
}

extension GeneralError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timeout(let message), .general(let message):
            return message
        }
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
    var settings: MergeSettings

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
                                      inputFieldResolver: .disabled)
    }

    func importBackup(url: URL, side: MergeSide) async throws {
        addBreadcrumb("importBackup from \(url.absoluteString) for side \(side.rawValue)")
        self.dbWrapper.skipPlaylists(true)

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

    func exportBackup() async throws -> String {
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
            SentrySDK.capture(error: error)
            print("Error while trying to clean up old files")
        }
    }

    // cleanUpInbox removes all files inside the inbox
    func cleanUpInbox() {
        let fm = FileManager.default
        do {
            let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox")
            let files = try fm.contentsOfDirectory(at: dir!.absoluteURL,
                                                   includingPropertiesForKeys: [.isRegularFileKey])
            for file in files {
                try fm.removeItem(at: file)
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

    func merge(reset: Bool = true, progress: MergeProgress) async throws {
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

    func nextConflict() throws -> MergeConflict {
        addBreadcrumb("nextConflict")
        do {
            let conflict = try self.mergeConflicts.nextConflict()
            let left = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                from: conflict.left.data(using: .utf8)!)
            let right = try JSONDecoder().decode(ModelRelatedTuple.self,
                                                 from: conflict.right.data(using: .utf8)!)
            return MergeConflict(key: conflict.key, left: left, right: right)
        } catch {
            if error.localizedDescription.starts(with: "There are no unsolved conflicts") {
                throw MergeError.noConflicts
            }
            SentrySDK.capture(error: error)
            throw error
        }
    }
}

func captureError(_ error: Error, userInfo: [String: Any]?) {
    let nsError = error as NSError
    let wrappedError = NSError(domain: nsError.domain,
                               code: nsError.code,
                               userInfo: userInfo)
    SentrySDK.capture(error: wrappedError)
}

func addBreadcrumb(_ message: String) {
    let crumb = Breadcrumb()
    crumb.level = SentryLevel.info
    crumb.category = "merger-controller"
    crumb.message = message
    SentrySDK.addBreadcrumb(crumb)
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
