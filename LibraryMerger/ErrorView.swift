//
//  ErrorView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 30.12.21.
//

import SwiftUI

struct ErrorView: View {
    @Binding var error: String

    @AppStorage("enableSentry") private var enableSentry: Bool = false

    @State private var errorCopied: Bool = false
    @State private var openSentrySettings: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("😕 Something went wrong..")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                Spacer()
            }.padding(.bottom, 5)

            Text("errorView.reportError")
                .padding(.bottom)

            Text("The following error was returned:")
                .bold()
                .padding(.bottom, 1)

            Text(error)
                .font(.system(.body, design: .monospaced))
                .onTapGesture {
                    copyError()
                }
            HStack {
                Spacer()
                Button(errorCopied ? "Copied" : "Copy") {
                    copyError()
                }
                .foregroundColor(Color.white)
                .padding(8)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            Spacer()
            Text("errorView.sentryHint")
            HStack {
                Toggle(isOn: $enableSentry) {
                    Text("Share error reports and statistics")
                }
                .onChange(of: enableSentry) { _ in
                    setupSentry(enableSentry: enableSentry)
                }
            }
            Button {
                openSentrySettings.toggle()
            } label: {
                Text("Learn more")
            }

        }
        .padding()
        .sheet(isPresented: $openSentrySettings, content: {
            SettingsView(selection: "sentry")
        })
    }

    func copyError() {
        UIPasteboard.general.string = error
        errorCopied = true
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        // swiftlint:disable:next line_length
        ErrorView(error: .constant("Error while scanning results from SQLite database: sql: Scan error on column index 4, name \"Tagld\": converting NULL to int is unsupported"))
    }
}
