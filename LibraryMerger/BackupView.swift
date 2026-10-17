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

    @AppStorage("warnOnPlaylist") private var warnOnPlaylist: Bool = true

    @Binding var sharedUrl: URL?
    @Binding var fileSelected: Bool
    @Binding var doneMerging: Bool

    @State private var isSelectingFile: Bool = false
    @State private var isImporting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showPlaylistWarning: Bool = false

    private var playlistsSkipped: Bool {
        mergerController.dbWrapper.dbContainsUnsupportedPlaylists(side.rawValue)
    }

    var body: some View {
        ZStack {
            // Reserves the height of a loaded backup, so the cards keep the same size in every state.
            loadedView(stats: GomobileDatabaseStats(), playlistsSkipped: true)
                .hidden()

            if isImporting {
                ProgressView()
            } else if !fileSelected {
                VStack {
                    Button(action: {
                        Task {
                            await wasPressed()
                        }
                    }, label: {
                        Image(systemName: "square.and.arrow.down")
                    })
                    .font(.title)
                    .padding()
                    Text("Select Backup")
                        .foregroundColor(.black)
                }
            } else {
                loadedView(stats: mergerController.dbWrapper.stats(side.rawValue) ?? GomobileDatabaseStats(),
                           playlistsSkipped: playlistsSkipped)
            }
        }
        .if(sharedUrl != nil) { view in
            view.blur(radius: 10.0)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .overlay {
            if sharedUrl != nil {
                VStack {
                    Button(action: {
                        Task {
                            await wasPressed()
                        }
                    }, label: {
                        Image(systemName: "plus.circle")
                    })
                        .font(.title)
                        .padding()
                    Text("Import")
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.5))
            }
        }
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
        )
        .shadow(color: Color.gray.opacity(0.2), radius: 20)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await wasPressed()
            }
        }
        .sheet(isPresented: $showError) {
            if errorMessage.lowercased().contains("backup incompatible") {
                BackupIncompatibleView(error: $errorMessage)
            } else {
                ErrorView(error: $errorMessage)
            }
        }
        .sheet(isPresented: $showPlaylistWarning) {
            PlaylistWarningView()
        }
        .fileImporter(isPresented: $isSelectingFile,
                      allowedContentTypes: [.jwlibrary]) { (result) in
            Task {
                isImporting.toggle()
                do {
                    let url = try result.get()
                    await importBackup(url: url)
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
                isImporting = false
            }
        }
    }

    private func loadedView(stats: GomobileDatabaseStats, playlistsSkipped: Bool) -> some View {
        VStack {
            VStack(alignment: .custom) {
                statRow("Bookmarks:", stats.bookmark)
                statRow("Notes:", stats.note)
                // JW Library stores playlists as tags, so they are counted separately.
                statRow("Tags:", stats.tag - stats.playlist)
                statRow("Taggings:", stats.tagMap)
                statRow("Markings:", stats.userMark)
                statRow("Input fields:", stats.inputField)
                statRow("Playlists:", stats.playlist)
            }
            .padding(.vertical)
            .padding(.bottom, -10)
            .if(UIScreen.main.bounds.size.width <= 380) { view in
                view.font(.callout)
            }

            if playlistsSkipped {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)

                    Text("Playlists skipped")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.orange)
                        .padding(.bottom)
                }
                .onTapGesture {
                    showPlaylistWarning.toggle()
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundColor(.green)
                    .padding(.bottom)
            }
        }
    }

    private func statRow(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(title).bold()
                .padding(.trailing, -7)
            Text(String(value))
                .font(.callout)
                .alignmentGuide(.custom) { $0[.leading] }
        }
    }

    func wasPressed() async {
        doneMerging = false
        if sharedUrl != nil {
            await importBackup(url: sharedUrl!)
            sharedUrl = nil
        } else {
            isSelectingFile.toggle()
        }
    }

    func importBackup(url: URL) async {
        do {
            try await mergerController.importBackup(url: url, side: side)
            fileSelected = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        if playlistsSkipped && warnOnPlaylist {
            showPlaylistWarning.toggle()
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
