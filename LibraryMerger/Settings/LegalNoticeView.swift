//
//  LegalNoticeView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 22.02.26.
//

import SwiftUI

struct LegalNoticeView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("legalNotice.body")
            Spacer()
        }
        .padding()
        .navigationBarTitle("Legal Notice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalNoticeView_Previews: PreviewProvider {
    static var previews: some View {
        LegalNoticeView()
    }
}
