//
//  BackupView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//  Copyright © 2020 Andreas Skorczyk. All rights reserved.
//

import SwiftUI
import Gomobile

struct BackupView: View {
    var side: MergeSide
    @ObservedObject var mergerController: MergerController

    @Binding var sharedUrl: URL?
    @Binding var fileSelected: Bool
    @Binding var doneMerging: Bool

    @State private var isSelectingFile: Bool = false
    @State private var isImporting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var dbStats: GomobileDatabaseStats = GomobileDatabaseStats()
    @State private var pickerSessionID: UUID?

    var body: some View {
        let screenWidth = UIScreen.main.bounds.size.width
        VStack {
            ZStack {
                VStack {
                    if isImporting {
                        ProgressView()
                    } else if !fileSelected {
                        Button(action: {
                            beginSelection()
                        }, label: {
                            Image(systemName: "square.and.arrow.down")
                        })
                        .accessibilityIdentifier("select-backup-\(side.rawValue)")
                        .font(.title)
                        .padding()
                        Text("Select Backup")
                            .foregroundColor(.black)
                    } else {
                        VStack(alignment: .custom) {

                            HStack {
                                Text("Bookmarks:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.bookmark))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }

                            HStack {
                                Text("Notes:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.note))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }

                            HStack {
                                Text("Tags:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.tag))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }

                            HStack {
                                Text("Taggings:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.tagMap))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }

                            HStack {
                                Text("Markings:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.userMark))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }

                            HStack {
                                Text("Input fields:").bold()
                                    .padding(.trailing, -7)
                                Text(String(dbStats.inputField))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }
                            HStack {
                                Text("Playlists:").bold().padding(.trailing, -7)
                                Text(String(dbStats.playlist))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }
                            HStack {
                                Text("Playlist items:").bold().padding(.trailing, -7)
                                Text(String(dbStats.playlistItem))
                                    .font(.callout)
                                    .alignmentGuide(.custom) { $0[.leading] }
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, -10)
                        .if(screenWidth <= 380) { view in
                            view.font(.callout)
                        }

                        Image(systemName: "checkmark.circle")
                            .font(.title)
                            .foregroundColor(.green)
                            .padding(.bottom)
                    }
                }
                .if(sharedUrl != nil) { view in
                    view.blur(radius: 10.0)
                }

                if sharedUrl != nil {
                    VStack {
                        Button(action: {
                            beginSelection()
                        }, label: {
                            Image(systemName: "plus.circle")
                        })
                            .font(.title)
                            .padding()
                        Text("Import")
                            .foregroundColor(.black)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
        )
        .shadow(color: Color.gray.opacity(0.2), radius: 20)
        .contentShape(Rectangle())
        .onTapGesture {
            beginSelection()
        }
        .sheet(isPresented: $showError) {
            if errorMessage.lowercased().contains("backup incompatible") {
                BackupIncompatibleView(error: $errorMessage)
            } else if isPlaylistError(errorMessage) {
                PlaylistWarningView(error: errorMessage)
            } else {
                ErrorView(error: $errorMessage)
            }
        }
        .fileImporter(isPresented: $isSelectingFile,
                      allowedContentTypes: [.jwlibrary]) { (result) in
            addBreadcrumb("file-picker.result", data: ["side": side.rawValue])
            guard let requestedSessionID = pickerSessionID,
                  requestedSessionID == mergerController.sessionID else { return }
            Task {
                guard requestedSessionID == mergerController.sessionID else { return }
                isImporting = true
                do {
                    let url = try result.get()
                    await importBackup(url: url, sessionID: requestedSessionID)
                } catch {
                    guard requestedSessionID == mergerController.sessionID else { return }
                    isImporting = false
                    if MergerDiagnostics.isCancellation(error) { return }
                    captureError(error, operation: "import", stage: "file-picker", side: side)
                    errorMessage = error.localizedDescription
                    showError = true
                }
                if requestedSessionID == mergerController.sessionID { isImporting = false }
            }
        }
        .onChange(of: isSelectingFile) { presented in
            addBreadcrumb(presented ? "file-picker.present" : "file-picker.dismiss",
                          data: ["side": side.rawValue])
        }
    }

    @MainActor
    private func beginSelection() {
        let requestedSessionID = mergerController.sessionID
        Task { await wasPressed(sessionID: requestedSessionID) }
    }

    @MainActor
    func wasPressed(sessionID: UUID) async {
        guard sessionID == mergerController.sessionID else { return }
        doneMerging = false
        if let url = sharedUrl {
            let imported = await importBackup(url: url, sessionID: sessionID)
            if sessionID == mergerController.sessionID && imported { sharedUrl = nil }
        } else {
            pickerSessionID = sessionID
            isSelectingFile = true
        }
    }

    @MainActor
    @discardableResult
    func importBackup(url: URL, sessionID: UUID) async -> Bool {
        guard sessionID == mergerController.sessionID else { return false }
        isImporting = true
        defer { if sessionID == mergerController.sessionID { isImporting = false } }
        do {
            try await mergerController.importBackup(url: url, side: side, sessionID: sessionID)
            guard sessionID == mergerController.sessionID else { return false }
            guard let stats = mergerController.dbWrapper.stats(side.rawValue) else {
                throw MergeError.notInitialized(message: "The imported backup could not be read")
            }
            dbStats = stats
            fileSelected = true
            return true
        } catch {
            guard sessionID == mergerController.sessionID else { return false }
            if MergerDiagnostics.isCancellation(error) { return false }
            errorMessage = error.localizedDescription
            showError = true
            return false
        }

    }
}

struct BackupView_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        BackupView(side: MergeSide.leftSide, mergerController: mergerController,
                   sharedUrl: .constant(nil),
                   fileSelected: .constant(false),
                   doneMerging: .constant(false))
    }
}
