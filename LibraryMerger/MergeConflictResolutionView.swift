//
//  MergeConflictView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 12.10.20.
//

import SwiftUI
import Gomobile

struct MergeConflictResolutionView: View {
    @ObservedObject var mergerController: MergerController
    @Environment(\.presentationMode) var presentationMode
    @Binding private var cancelMerge: Bool
    @State private var conflict: MergeConflict
    @State private var selectedSide: MergeSide?
    @State private var helpOpened = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @AppStorage("showMarkingText") private var showMarkingText = false
    @AppStorage("markingTextInfoShown") private var markingTextInfoShown = false
    @State private var showMarkingTextInfo = false
    // The marked paragraphs of each side, once they are loaded
    @State private var snippets: [MergeSide: [MarkingSnippet]] = [:]
    @State private var markingTextFailed = false
    @State private var download = (key: "", downloaded: Int64(0), total: Int64(-1))
    // Trying again to load the text starts a new lookup
    @State private var markingTextAttempt = 0
    @State private var scrollLink = ScrollLink()

    init (mergerController: MergerController, cancelMerge: Binding<Bool>) {
        self.mergerController = mergerController
        self._cancelMerge = cancelMerge
        do {
            try _conflict = State(initialValue: mergerController.nextConflict())
        } catch {
            _conflict = State(initialValue: MergeConflict(key: "", left: nil, right: nil))
            _errorMessage = State(initialValue: error.localizedDescription)
            _showError = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationView {
            // The whole conflict scrolls, so both choices stay reachable at large text sizes.
            ScrollView {
                VStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Conflict while merging")
                                + Text(" \(NSLocalizedString(getConflictType(), comment: "Name of the conflict")).")
                                    .bold()

                            Spacer()

                            Button(action: {
                                helpOpened.toggle()
                            }, label: {
                                Image(systemName: "questionmark.circle")
                            })
                            .sheet(isPresented: $helpOpened) {
                                HelpView(isPresented: $helpOpened,
                                         title: NSLocalizedString("help.conflict.\(getConflictType()).title",
                                                                  comment: "Title for specific conflict help text"),
                                         helpText: NSLocalizedString("help.conflict.\(getConflictType()).text",
                                                                  comment: "Help text for specific conflict"))
                            }
                        }
                        Text(question)
                        if conflict.changedFields.count > 1 {
                            Text("Choose one version. All settings shown in that version will be kept.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    MergeConflictOverview(mrt: conflict.left, thumbnail: conflict.thumbnail)
                        .padding(.top)

                    VStack {
                        MergeConflictDetailsView(conflict: conflict,
                                                 side: .leftSide,
                                                 markingText: markingText(.leftSide))
                            .if((selectedSide == MergeSide.leftSide)) { view in
                                view.overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue, lineWidth: 1))
                            }
                            .padding(.top, 40)
                            .padding(.horizontal)
                            .padding(.bottom, 10)
                            .onTapGesture(count: 1, perform: {
                                selectedSide = .leftSide
                            })
                            .accessibilityIdentifier("conflict-left")

                        MergeConflictDetailsView(conflict: conflict,
                                                 side: .rightSide,
                                                 markingText: markingText(.rightSide))
                            .if((selectedSide == MergeSide.rightSide)) { view in
                                view.overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue, lineWidth: 1))
                            }
                            .padding(.horizontal)
                            .onTapGesture(count: 1, perform: {
                                selectedSide = .rightSide
                            })
                            .accessibilityIdentifier("conflict-right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom)
                }
            }
            .task(id: "\(conflict.key) \(showMarkingText) \(markingTextAttempt)") {
                markingTextFailed = false
                guard showMarkingText, hasMarkingText else { return }
                let key = conflict.key
                download = (key, 0, -1)
                // Both sides share one download, and progress of an earlier conflict's download is ignored
                let listener = DownloadListener { downloaded, total in
                    if download.key == key {
                        download = (key, downloaded, total)
                    }
                }
                async let left = mergerController.markingSnippets(key: key, side: .leftSide, listener: listener)
                async let right = mergerController.markingSnippets(key: key, side: .rightSide, listener: listener)
                // The lookup can't be stopped, so its result may arrive after the next conflict is shown
                do {
                    let loaded = try await [MergeSide.leftSide: left, .rightSide: right]
                    guard !Task.isCancelled else { return }
                    snippets = loaded
                } catch {
                    guard !Task.isCancelled else { return }
                    markingTextFailed = true
                }
            }
            .sheet(isPresented: $showMarkingTextInfo) {
                MarkingTextInfo(showText: {
                    markingTextInfoShown = true
                    showMarkingText = true
                    showMarkingTextInfo = false
                }, notNow: {
                    showMarkingTextInfo = false
                })
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: (
                Button(action: {
                    cancelMerge = true
                    presentationMode.wrappedValue.dismiss()
                }, label: {
                    Text("Cancel")
                }).accessibilityIdentifier("cancel-conflicts")), trailing: (
                Button(action: {
                    do {
                        try mergerController.mergeConflicts.solveConflict(conflict.key, side: selectedSide?.rawValue)
                        try conflict = mergerController.nextConflict()
                        selectedSide = nil
                        snippets = [:]
                    } catch MergeError.noConflicts {
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError.toggle()
                    }
                }, label: {
                    Text("Continue")
                }).disabled(selectedSide == nil)
                .accessibilityIdentifier("continue-conflicts")
                )
            )
        }
        .sheet(isPresented: $showError) {
            ErrorView(error: $errorMessage)
        }
    }

    // Markings in paragraphs of publications (block type 1) and in Bible verses (block type 2) have text to show
    var hasMarkingText: Bool {
        guard case .userMarkBlockRange(let umbr) = conflict.left?.model else { return false }
        return umbr.blockRanges.contains { $0.blockType == 1 || $0.blockType == 2 }
    }

    func markingText(_ side: MergeSide) -> MarkingText {
        MarkingText(enabled: showMarkingText, available: hasMarkingText, snippets: snippets[side],
                    failed: markingTextFailed,
                    downloaded: download.downloaded, total: download.total,
                    load: {
                        // The first time, a short explanation tells where the text comes from
                        if showMarkingText {
                            snippets = [:]
                            markingTextAttempt += 1
                        } else if markingTextInfoShown {
                            showMarkingText = true
                        } else {
                            showMarkingTextInfo = true
                        }
                    },
                    hide: { showMarkingText = false },
                    link: scrollLink,
                    select: { selectedSide = side },
                    otherSnippets: snippets[side == .leftSide ? .rightSide : .leftSide])
    }

    var question: String {
        if conflict.changedFields.count == 1 {
            return conflict.changedFields[0].question
        } else if !conflict.changedFields.isEmpty {
            return NSLocalizedString("Which settings should this item use?", comment: "Playlist conflict question")
        }
        return NSLocalizedString("Which one should be included?", comment: "Conflict question")
    }

    func getConflictType() -> String {
        let left = conflict.left?.model
        switch left {
        case .bookmark:
            return "bookmarks"
        case .userMarkBlockRange:
            return "markings"
        case .note:
            return "notes"
        case .inputField:
            return "input fields"
        case .playlistItem, .playlistItemLocationMap, .playlistItemIndependentMediaMap:
            return "playlist items"
        default:
            return "error"
        }
    }
}

struct MergeConflictViewResolution_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        MergeConflictResolutionView(mergerController: mergerController, cancelMerge: .constant(false))
    }
}
