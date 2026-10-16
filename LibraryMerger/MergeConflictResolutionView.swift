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
                                                 side: .leftSide)
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
                                                 side: .rightSide)
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
