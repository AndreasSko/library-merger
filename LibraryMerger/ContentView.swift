//
//  ContentView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import SwiftUI
import Gomobile

struct ContentView: View {
    @ObservedObject var mergerController: MergerController

    @State private var showCatalogNotification: Bool = checkCatalogNotification()
    @State private var sharedUrl: URL?
    @State private var leftSelected: Bool = false
    @State private var rightSelected: Bool = false
    @State private var doneMerging: Bool = false
    @State private var openSettings: Bool = false
    @State private var openCatalogSettings: Bool = false

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("Library Merger")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                Spacer()
                if leftSelected || rightSelected {
                    Button("New merge") {
                        mergerController.resetSession()
                        leftSelected = false
                        rightSelected = false
                        doneMerging = false
                        sharedUrl = nil
                    }
                    .disabled(mergerController.isBusy)
                    .accessibilityIdentifier("new-merge")
                }
            }
            .padding()
            VStack {
                HStack {
                    BackupView(side: MergeSide.leftSide,
                               mergerController: mergerController,
                               sharedUrl: $sharedUrl,
                               fileSelected: $leftSelected,
                               doneMerging: $doneMerging)
                        .id("\(mergerController.sessionID)-left")
                    BackupView(side: MergeSide.rightSide,
                               mergerController: mergerController,
                               sharedUrl: $sharedUrl,
                               fileSelected: $rightSelected,
                               doneMerging: $doneMerging)
                        .id("\(mergerController.sessionID)-right")
                }.padding(.horizontal)
                    .disabled(mergerController.isBusy || mergerController.conflictResolutionID != nil)
            }

            MergeSettingsView(mergerController: mergerController)
                .disabled(mergerController.isBusy || mergerController.conflictResolutionID != nil)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
                )
                .shadow(color: Color.gray.opacity(0.2), radius: 20)
                .padding([.top, .horizontal])

            MergeView(mergerController: mergerController,
                      enabled: leftSelected && rightSelected,
                      doneMerging: $doneMerging)
                .id(mergerController.sessionID)

            Spacer()

            VStack {
                if showCatalogNotification {
                    NotificationView(text1: "New version of the Publication Catalog is available.",
                                     text2: "You can download it in the settings.")
                        .onTapGesture {
                            UserDefaults.standard.set(Date(),
                                                      forKey: "lastCatalogNotification")
                            showCatalogNotification = false
                            openCatalogSettings.toggle()
                        }
                }
            }
            .sheet(isPresented: $openCatalogSettings, content: {
                SettingsView(selection: "catalog")
            })

            Button(action: {
                openSettings.toggle()
            }, label: {
                Image(systemName: "gear")
            })
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $openSettings, content: {
                SettingsView()
            })
        }
        .onOpenURL { url in
            sharedUrl = url
        }
        #if DEBUG
        .task {
            // UI tests supply task-owned archives; release builds have no fixture entry point.
            let environment = ProcessInfo.processInfo.environment
            guard ProcessInfo.processInfo.arguments.contains("--playlist-ui-test"),
                  let left = environment["PLAYLIST_TEST_LEFT"],
                  let right = environment["PLAYLIST_TEST_RIGHT"] else { return }
            do {
                try await mergerController.importBackup(url: URL(fileURLWithPath: left), side: .leftSide)
                try await mergerController.importBackup(url: URL(fileURLWithPath: right), side: .rightSide)
                leftSelected = true
                rightSelected = true
            } catch {
                assertionFailure("UI fixture import failed: \(error)")
            }
        }
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        ContentView(mergerController: mergerController)
    }
}

// checkCatalogNotification determines if the catalog notification should be shown
func checkCatalogNotification() -> Bool {
    if !GomobileCatalogNeedsUpdate(catalogDBPath?.path) {
        return false
    }

    let lastNotification = UserDefaults.standard.object(forKey: "lastCatalogNotification")
    if lastNotification == nil {
        return true
    }

    var month = DateComponents()
    month.month = -1
    let monthAgo = Calendar.current.date(byAdding: month, to: Date())

    if lastNotification as? Date ?? Date() > monthAgo ?? Date() {
        return false
    }

    return true
}
