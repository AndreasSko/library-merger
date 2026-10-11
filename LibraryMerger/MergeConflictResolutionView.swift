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
    @Environment(\.sizeCategory) private var sizeCategory
    @Binding private var cancelMerge: Bool
    @State private var conflict: MergeConflict
    @State private var selectedSide: MergeSide?
    @State private var helpOpened = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    private let resolutionID: UUID?

    init (mergerController: MergerController, cancelMerge: Binding<Bool>, resolutionID: UUID? = nil) {
        self.mergerController = mergerController
        self._cancelMerge = cancelMerge
        self.resolutionID = resolutionID ?? mergerController.conflictResolutionID
        do {
            try _conflict = State(initialValue: mergerController.nextConflict(resolutionID: self.resolutionID))
        } catch {
            _conflict = State(initialValue: MergeConflict(key: "", left: nil, right: nil))
            _errorMessage = State(initialValue: error.localizedDescription)
            _showError = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Conflict while merging")
                            + Text(" \(NSLocalizedString(getConflictType(), comment: "Name of the conflict")).").bold()

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
                    .fixedSize(horizontal: false, vertical: true)
                    Text(NSLocalizedString(conflict.playlistPresentation?.question ?? "Which one should be included?",
                                           comment: "Question for the changed playlist setting"))
                        .fixedSize(horizontal: false, vertical: true)
                    if conflict.playlistPresentation?.choosesWholeVersion == true {
                        Text("Choose one version. All settings shown in that version will be kept.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()

                MergeConflictOverview(mrt: conflict.left)
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
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("conflict-scroll")
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: (
                Button(action: {
                    if let resolutionID = resolutionID {
                        mergerController.cancelConflictResolution(resolutionID)
                    }
                    cancelMerge = true
                    presentationMode.wrappedValue.dismiss()
                }, label: {
                    Text("Cancel")
                }).accessibilityIdentifier("cancel-conflicts")), trailing: (
                Button(action: {
                    do {
                        guard let currentResolutionID = resolutionID, let chosenSide = selectedSide else { return }
                        try mergerController.solveConflict(conflict.key, side: chosenSide,
                                                           resolutionID: currentResolutionID)
                        try conflict = mergerController.nextConflict(resolutionID: currentResolutionID)
                        selectedSide = nil
                    } catch MergeError.noConflicts {
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }, label: {
                    Text("Continue")
                }).disabled(selectedSide == nil || conflict.key.isEmpty || mergerController.isBusy
                            || resolutionID != mergerController.conflictResolutionID)
                    .accessibilityIdentifier("continue-conflicts")
                )
            )
        }
        .environment(\.sizeCategory, conflictSizeCategory)
        .sheet(isPresented: $showError) {
            ErrorView(error: $errorMessage)
        }
    }

    private var conflictSizeCategory: ContentSizeCategory {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--playlist-ui-test") && arguments.contains("--playlist-ui-test-largest-text") {
            return .accessibilityExtraExtraExtraLarge
        }
        #endif
        return sizeCategory
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
