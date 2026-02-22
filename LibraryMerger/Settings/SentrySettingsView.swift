//
//  SentrySettingsView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 13.11.22.
//

import SwiftUI

struct SentrySettingsView: View {
    @AppStorage("enableSentry") private var enableSentry: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("settings.sentry.explanation")
            HStack {
                Toggle(isOn: $enableSentry) {
                    Text("Share error reports and statistics")
                }
                .onChange(of: enableSentry) { _ in
                    setupSentry(enableSentry: enableSentry)
                }
            }
            Spacer()
        }
        .padding()
        .navigationBarTitle("Share Error Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SentrySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SentrySettingsView()
    }
}
