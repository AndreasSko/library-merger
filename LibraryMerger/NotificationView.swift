//
//  NotificationView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 16.12.20.
//

import SwiftUI

struct NotificationView: View {
    let text1: String
    let text2: String?

    init(text1: String) {
        self.text1 = text1
        self.text2 = nil
    }

    init(text1: String, text2: String) {
        self.text1 = text1
        self.text2 = text2
    }

    var body: some View {
        HStack {
            Image(systemName: "info.circle").accentColor(.green)
            VStack(alignment: .leading) {
                Text(NSLocalizedString(text1, comment: "First notification text"))
                if text2 != nil {
                    Text(NSLocalizedString(text2!, comment: "Second notification text"))
                }
            }.font(.footnote)
        }
        .contentShape(Rectangle())
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
        )
        .shadow(color: Color.gray.opacity(0.2), radius: 20)
        .padding([.top, .horizontal])
    }
}

struct NotificationView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationView(text1: "First line", text2: "Second line")
    }
}
