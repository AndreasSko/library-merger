import SwiftUI

// Also used from Settings to explain which playlist features are supported.
struct PlaylistWarningView: View {
    var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(error == nil ? "About playlist merging" : "Unable to merge playlists",
                      systemImage: error == nil ? "music.note.list" : "exclamationmark.triangle")
                    .font(.title)
                Text("playlist.support.explanation")
                if let error = error {
                    Text("playlist.support.failure")
                    Text(error).font(.footnote)
                }
            }
            .padding()
        }
    }
}

func isPlaylistError(_ message: String) -> Bool {
    let message = message.lowercased()
    return message.contains("playlist") || message.contains("independentmedia")
}
