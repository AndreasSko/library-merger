//
//  MergeView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 28.10.20.
//

import SwiftUI
import Gomobile

struct MergeView: View {
    @ObservedObject var mergerController: MergerController

    var enabled: Bool
    @Binding var doneMerging: Bool

    @State private var isMerging: Bool = false
    @StateObject private var mergeProgress = MergeProgress()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showMergeConflictSheet: Bool = false
    @State private var cancelMerge: Bool = false
    @State private var resolutionID: UUID?
    @State private var presentationSessionID: UUID?

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    let requestedSessionID = mergerController.sessionID
                    Task {
                        guard requestedSessionID == mergerController.sessionID else { return }
                        doneMerging = false
                        cancelMerge = false
                        isMerging = true
                        mergeProgress.percent = 1
                        mergeProgress.status = "Merging.."

                        let merged = await merge()
                        guard requestedSessionID == mergerController.sessionID else { return }
                        doneMerging = merged
                        isMerging = false
                    }

                }, label: {
                    Text("Merge")
                })
                .disabled(!enabled || mergerController.isBusy || isMerging
                          || mergerController.conflictResolutionID != nil)
                .accessibilityIdentifier("merge-backups")
            }
            .font(.title2)
            .padding()
            .sheet(isPresented: $showError) {
                if isPlaylistError(errorMessage) {
                    PlaylistWarningView(error: errorMessage)
                } else {
                    ErrorView(error: $errorMessage)
                }
            }
            .fullScreenCover(isPresented: $showMergeConflictSheet, onDismiss: {
                guard presentationSessionID == mergerController.sessionID else { return }
                let dismissedSessionID = presentationSessionID
                let dismissedResolutionID = resolutionID
                Task {
                    guard dismissedSessionID == mergerController.sessionID else { return }
                    if cancelMerge {
                        doneMerging = false
                        isMerging = false
                        mergeProgress.percent = 0
                    } else if dismissedResolutionID == mergerController.conflictResolutionID,
                              dismissedResolutionID != nil {
                        isMerging = true
                        let merged = await merge(reset: false, resolutionID: dismissedResolutionID)
                        guard dismissedSessionID == mergerController.sessionID else { return }
                        doneMerging = merged
                        isMerging = false
                    }
                }
            }, content: {
                MergeConflictResolutionView(mergerController: mergerController, cancelMerge: $cancelMerge,
                                            resolutionID: resolutionID)
            })

            if !doneMerging && mergeProgress.percent > 0 && mergeProgress.percent < 100 {
                ProgressView(mergeProgress.status, value: mergeProgress.percent, total: 100)
                    .padding()
                    .animation(.easeInOut(duration: 10))
            }

            if doneMerging {
                VStack {
                    Text("🎉").font(.title)
                    ExportView(mergerController: mergerController)
                }
            }
        }
    }

    @MainActor
    func merge(reset: Bool = true, resolutionID: UUID? = nil) async -> Bool {
        let sessionID = mergerController.sessionID
        do {
            try await mergerController.merge(reset: reset, progress: mergeProgress,
                                             resolutionID: resolutionID, sessionID: sessionID)
        } catch MergeError.mergeConflict {
            guard sessionID == mergerController.sessionID else { return false }
            self.resolutionID = mergerController.conflictResolutionID
            presentationSessionID = sessionID
            showMergeConflictSheet = true

            return false
        } catch {
            guard sessionID == mergerController.sessionID else { return false }
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
        return sessionID == mergerController.sessionID
    }
}

struct MergeView_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        MergeView(mergerController: mergerController,
                  enabled: true,
                  doneMerging: .constant(false))
    }
}
