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
    @State private var dbStats: GomobileDatabaseStats = GomobileDatabaseStats()
    @State private var containsPlaylists: Bool = true
    @State private var showPlaylistWarning: Bool = false

    var body: some View {
        let screenWidth = UIScreen.main.bounds.size.width
        VStack {
            ZStack {
                VStack {
                    if isImporting {
                        ProgressView()
                    } else if !fileSelected {
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
                        }
                        .padding(.vertical)
                        .padding(.bottom, -10)
                        .if(screenWidth <= 380) { view in
                            view.font(.callout)
                        }

                        if containsPlaylists {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                    .foregroundColor(.orange)

                                Text("Contains playlists")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.orange)
                                    .padding(.bottom)
                            }
                            .onTapGesture {
                                Task {
                                    showPlaylistWarning.toggle()
                                }
                            }
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.title)
                                .foregroundColor(.green)
                                .padding(.bottom)
                        }
                    }
                }
                .if(sharedUrl != nil) { view in
                    view.blur(radius: 10.0)
                }

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
            dbStats = mergerController.dbWrapper.stats(side.rawValue)!
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        containsPlaylists = mergerController.dbWrapper.dbContainsPlaylists(side.rawValue)
        if containsPlaylists && warnOnPlaylist {
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
