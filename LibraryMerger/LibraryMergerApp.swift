//
//  LibraryMergerApp.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import SwiftUI
import Gomobile
import Sentry

@main
struct LibraryMergerApp: App {
    @StateObject private var mergerController = MergerController()
    @AppStorage("needsOnboarding") private var needsOnboarding: Bool = true
    @AppStorage("enableSentry") private var enableSentry: Bool = false

    var body: some Scene {
        WindowGroup {
            if needsOnboarding {
                OnboardingView(needsOnboarding: $needsOnboarding)
            } else {
                ContentView(mergerController: mergerController)
            }
        }
    }

    init() {
        setupSentry(enableSentry: enableSentry)
    }

}

struct LibraryMergerApp_Previews: PreviewProvider {
    static var previews: some View {
        let mergerController = MergerController()
        ContentView(mergerController: mergerController)
    }
}

func setupSentry(enableSentry: Bool) {
    SentrySDK.start { options in
        options.enabled = enableSentry
        options.dsn = "https://e46082df0a5343d0bfe1615b169834ff@o1083063.ingest.sentry.io/4504147949780992"
        options.enableAutoSessionTracking = false
        options.enableNetworkTracking = false

        #if DEBUG
        options.beforeSend = { event in
            print("Sending: \(event)")
            return event
        }
        #endif
    }
}
