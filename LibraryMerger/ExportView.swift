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
                Task {
                    isExporting = true
                    do {
                        let path = try await mergerController.exportBackup()
                        isExporting = false
                        exportedURL = NSURL.fileURL(withPath: path)
                        isSharing.toggle()
                    } catch {
                        isExporting = false
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            if isExporting {
                ProgressView()
            }
        }
        .sheet(isPresented: $showError) {
            ErrorView(error: $errorMessage)
        }
        .sheet(isPresented: $isSharing, onDismiss: {
            addBreadcrumb("share-sheet.dismiss")
        }, content: {
            ShareView(url: self.$exportedURL)
        })
    }
}

struct ShareView: UIViewControllerRepresentable {
    @Binding var url: URL!

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareView>) -> UIActivityViewController {
        addBreadcrumb("share-sheet.create")
        let started = ProcessInfo.processInfo.systemUptime
        let controller = UIActivityViewController(activityItems: [url!],
                                                  applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let details: [String: Any] = [
                "completed": completed,
                "seconds": ProcessInfo.processInfo.systemUptime - started
            ]
            addBreadcrumb("share-sheet.complete", data: details)
            if let error {
                captureError(error, operation: "export", stage: "share-sheet", details: details)
            }
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
