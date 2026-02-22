//
//  MergeSettingsLegendHelp.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 23.03.21.
//

import SwiftUI

struct MergeSettingsLegendHelp: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Legend:")
                .font(.title2)
                .padding(.vertical, 5)

            VStack(alignment: .custom) {
                HStack {
                    Image(systemName: "bookmark")
                    Text("Bookmarks")
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                HStack {
                    Image(systemName: "pencil.tip")
                    Text("Markings")
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                HStack {
                    Image(systemName: "note.text")
                    Text("Notes")
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                HStack {
                    Image(systemName: "textbox")
                    Text("Input fields")
                        .alignmentGuide(.custom) { $0[.leading] }
                }
            }
        }
        .padding(.top, 40)
    }
}

struct MergeSettingsLegendHelp_Previews: PreviewProvider {
    static var previews: some View {
        MergeSettingsLegendHelp()
    }
}
