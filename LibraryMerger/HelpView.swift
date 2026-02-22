//
//  HelpPopupView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 13.11.20.
//

import SwiftUI

struct HelpView: View {
    @Binding var isPresented: Bool
    var title: String?
    var helpText: String?
    var additionalViews: [AnyView]?

    init(isPresented: Binding<Bool>, title: String, helpText: String) {
        self._isPresented = isPresented
        self.title = title
        self.helpText = helpText
    }

    init(isPresented: Binding<Bool>, title: String, helpText: String,
         additionalViews: [AnyView]) {
        self._isPresented = isPresented
        self.title = title
        self.helpText = helpText
        self.additionalViews = additionalViews
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                Button("Done") {
                    isPresented.toggle()
                }
            }
            .padding(.top)

            Divider()

            VStack(alignment: .leading) {
                Text(title ?? "").font(.title3).padding(.bottom)
                Text(helpText ?? "")
            }

            if additionalViews?.isEmpty == false {
                ForEach(0..<additionalViews!.count) { index in
                    additionalViews![index]
                }
            }

            Spacer()
        }
        .padding(.horizontal)

    }
}

struct HelpPopupView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView(
            isPresented: .constant(true),
            title: "A title",
            helpText: "This is a help text..",
            additionalViews: [AnyView(MergeSettingsLegendHelp())])
    }
}
