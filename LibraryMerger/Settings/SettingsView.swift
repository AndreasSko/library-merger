//
//  SettingsView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 07.12.20.
//

import SwiftUI

struct SettingsView: View {
    @State var selection: String?
    @AppStorage("warnOnPlaylist") private var warnOnPlaylist: Bool = true

    init() {}
    init(selection: String) {
        self._selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink(destination: CatalogDBSettingsView(),
                                   tag: "catalog",
                                   selection: $selection) {
                        Text("Manage Publication Catalog")
                    }

                    NavigationLink(destination: SentrySettingsView(),
                                   tag: "sentry",
                                   selection: $selection) {
                        Text("Share Error Reports")
                    }

                    Button(action: {
                        UserDefaults.standard.removeObject(forKey: "needsOnboarding")
                    }, label: {
                        Text("Show Tutorial again")
                    })

                    Toggle(isOn: $warnOnPlaylist) {
                        Text("Warn if backup contains playlist")
                    }

                    #if DEBUG
                    Button(action: {
                        UserDefaults.standard.removeObject(forKey: "lastCatalogNotification")
                    }, label: {
                        Text("Show Notification again")
                    })
                    #endif
                }

                Section {
                    Link("Can I Support this App?",
                         destination: URL(string: "https://github.com/AndreasSko/library-merger"
                                          + "/wiki/Can-I-Support-the-Library-Merger%3F")!)

                    Link("Open Issue on GitHub",
                         destination: URL(string: "https://github.com/AndreasSko/library-merger/issues/new/choose")!)

                    Link("Review Privacy Policy",
                         destination: URL(string: "https://github.com/AndreasSko/library-merger/wiki/Privacy-Policy")!)

                    Link(destination:
                            URL(string: "https://github.com/AndreasSko/library-merger")!,
                         label: {
                            HStack {
                                Image("github")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 25)
                                Text("Visit project on GitHub")
                            }
                    })
                }

            }
            .navigationBarTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
