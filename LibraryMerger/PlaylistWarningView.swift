//
//  PlaylistWarningView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 19.07.23.
//

import SwiftUI

struct PlaylistWarningView: View {

    @AppStorage("warnOnPlaylist") private var warnOnPlaylist: Bool = true

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("Can't merge playlists",
                      systemImage: "exclamationmark.triangle")
                .font(.title)
                Spacer()
            }.padding(.bottom, 5)

            Text("playlistWarningView.explanation")
            Spacer()
            HStack {
                Toggle(isOn: $warnOnPlaylist) {
                    Text("Warn if backup contains playlist")
                }
            }
        }
        .padding()
    }
}

struct PlaylistWarningView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistWarningView()
    }
}
