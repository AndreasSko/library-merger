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
    @State private var shareItem: BackupShareItem?
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
                        shareItem = BackupShareItem(url: URL(fileURLWithPath: path))
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
        .sheet(item: $shareItem, onDismiss: {
            addBreadcrumb("share-sheet.dismiss")
        }, content: { item in
            ShareView(url: item.url)
        })
    }
}

struct ShareView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareView>) -> UIActivityViewController {
        addBreadcrumb("share-sheet.create")
        let started = ProcessInfo.processInfo.systemUptime
        let controller = UIActivityViewController(activityItems: [url],
                                        applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let details: [String: Any] = [
                "completed": completed, "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started
            ]
            addBreadcrumb("share-sheet.complete", data: details)
            if let error { captureError(error, operation: "export", stage: "share-sheet", details: details) }
        }
        return controller
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
