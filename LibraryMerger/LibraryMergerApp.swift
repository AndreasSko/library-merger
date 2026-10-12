//
//  LibraryMergerApp.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import SwiftUI
import Gomobile

@main
struct LibraryMergerApp: App {
    @StateObject private var mergerController = MergerController()
    @AppStorage("needsOnboarding") private var needsOnboarding: Bool = true
    @AppStorage("enableSentry") private var enableSentry: Bool = false

    var body: some Scene {
        WindowGroup {
            if needsOnboarding && !isPlaylistUITest {
                OnboardingView(needsOnboarding: $needsOnboarding)
            } else {
                ContentView(mergerController: mergerController)
            }
        }
    }

    init() {
        setupSentry(enableSentry: enableSentry)
    }

    private var isPlaylistUITest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--playlist-ui-test")
        #else
        return false
        #endif
    }

}

struct LibraryMergerApp_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        ContentView(mergerController: mergerController)
    }
}
