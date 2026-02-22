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
    @ObservedObject private var mergeProgress: MergeProgress = MergeProgress()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showMergeConflictSheet: Bool = false
    @State private var cancelMerge: Bool = false

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    Task {
                        doneMerging = false
                        cancelMerge = false
                        isMerging = true
                        mergeProgress.percent = 1
                        mergeProgress.status = "Merging.."

                        doneMerging = await merge()
                        isMerging = false
                    }

                }, label: {
                    Text("Merge")
                })
                .disabled(!enabled)
            }
            .font(.title2)
            .padding()
            .sheet(isPresented: $showError) {
                ErrorView(error: $errorMessage)
            }
            .fullScreenCover(isPresented: $showMergeConflictSheet, onDismiss: {
                Task {
                    if cancelMerge {
                        doneMerging = false
                        isMerging = false
                        mergeProgress.percent = 0
                    } else {
                        doneMerging = await merge(reset: false)
                    }
                }
            }, content: {
                MergeConflictResolutionView(mergerController: mergerController, cancelMerge: $cancelMerge)
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

    func merge(reset: Bool = true) async -> Bool {
        do {
            try await mergerController.merge(reset: reset, progress: mergeProgress)
        } catch MergeError.mergeConflict {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showMergeConflictSheet.toggle()
            }

            return false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
        return true
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
