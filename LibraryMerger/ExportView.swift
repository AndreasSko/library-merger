//
//  ExportView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 12.10.20.
//

import SwiftUI

struct ExportView: View {
    @ObservedObject var mergerController: MergerController

    @State private var isExporting: Bool = false
    @State private var isSharing: Bool = false
    @State private var exportedURL: URL!
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack {
            Button("Export") {
                let requestedSessionID = mergerController.sessionID
                Task {
                    guard requestedSessionID == mergerController.sessionID else { return }
                    isExporting = true
                    do {
                        let path = try await mergerController.exportBackup(sessionID: requestedSessionID)
                        guard requestedSessionID == mergerController.sessionID else { return }
                        isExporting = false
                        exportedURL = NSURL.fileURL(withPath: path)
                        isSharing = true
                    } catch {
                        guard requestedSessionID == mergerController.sessionID else { return }
                        isExporting = false
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .disabled(isExporting || mergerController.isBusy)
            if isExporting {
                ProgressView()
            }
        }
        .sheet(isPresented: $showError) {
            if isPlaylistError(errorMessage) {
                PlaylistWarningView(error: errorMessage)
            } else {
                ErrorView(error: $errorMessage)
            }
        }
        .sheet(isPresented: $isSharing, content: {
            ShareView(url: self.$exportedURL)
        })
    }
}

struct ShareView: UIViewControllerRepresentable {
    @Binding var url: URL!

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareView>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [url!],
                                        applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: UIViewControllerRepresentableContext<ShareView>) {

    }
}

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        ExportView(mergerController: mergerController)
    }
}
