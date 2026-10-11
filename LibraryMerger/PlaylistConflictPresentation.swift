import Foundation
import SwiftUI

enum PlaylistSourceLink {
    static func validatedURL(_ source: String?) -> URL? {
        guard let source = source, let url = URL(string: source), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host == "jw.org" || host.hasSuffix(".jw.org"),
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct PlaylistContextRow: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

struct PlaylistContextPresentation {
    let rows: [PlaylistContextRow]

    init(related: Related?, publication: Publication?, itemTitle: String?) {
        var rows: [PlaylistContextRow] = []
        if let location = related?.location {
            let title = location.title.valid && !location.title.string.isEmpty ? location.title.string : itemTitle
            if let title = title, !title.isEmpty { rows.append(.init(key: "Title:", value: title)) }
            if let publication = publication, !publication.title.isEmpty {
                rows.append(.init(key: "Publication:", value: publication.title))
                if !publication.issueTitle.isEmpty {
                    rows.append(.init(key: "Issue:", value: publication.issueTitle))
                }
            }
        }
        if let media = related?.independentMedia {
            rows.append(.init(key: "Media:", value: media.originalFilename))
        }
        if let tag = related?.tag { rows.append(.init(key: "Playlist:", value: tag.name)) }
        self.rows = rows
    }
}

// Go supplies the fields that require a choice. Swift only validates and formats
// that contract; it never compares backups or determines merge identity.
enum PlaylistChangedField: String, Decodable, CaseIterable {
    case label, startTrimOffsetTicks, endTrimOffsetTicks, accuracy, endAction
    case baseDurationTicks, majorMultimediaType, durationTicks

    var title: String {
        switch self {
        case .label: return "Name:"
        case .startTrimOffsetTicks: return "Start trim:"
        case .endTrimOffsetTicks: return "End trim:"
        case .accuracy: return "Accuracy:"
        case .endAction: return "End action:"
        case .baseDurationTicks, .durationTicks: return "Duration:"
        case .majorMultimediaType: return "Media type:"
        }
    }

    var question: String {
        switch self {
        case .label: return "What should this item be called?"
        case .startTrimOffsetTicks: return "Where should playback start?"
        case .endTrimOffsetTicks: return "Where should playback stop?"
        case .accuracy: return "Which timing accuracy should be used?"
        case .endAction: return "What should happen when this item finishes?"
        case .baseDurationTicks, .durationTicks: return "How long should this item play?"
        case .majorMultimediaType: return "Which media type should be used?"
        }
    }

    func value(in model: Model) throws -> String {
        switch (model, self) {
        case (.playlistItem(let item), .label): return item.label
        case (.playlistItem(let item), .startTrimOffsetTicks): return trim(item.startTrimOffsetTicks)
        case (.playlistItem(let item), .endTrimOffsetTicks): return trim(item.endTrimOffsetTicks)
        case (.playlistItem(let item), .accuracy): return String(item.accuracy)
        case (.playlistItem(let item), .endAction):
            return NSLocalizedString(item.endActionName, comment: "Playlist end action")
        case (.playlistItemLocationMap(let mapping), .baseDurationTicks): return trim(mapping.baseDurationTicks)
        case (.playlistItemLocationMap(let mapping), .majorMultimediaType):
            return mediaType(mapping.majorMultimediaType)
        case (.playlistItemIndependentMediaMap(let mapping), .durationTicks):
            return formatPlaylistTicks(mapping.durationTicks)
        default: throw PlaylistConflictPresentation.invalidMetadata
        }
    }

    private func trim(_ ticks: NullInt64) -> String {
        ticks.valid ? formatPlaylistTicks(ticks.int64) : NSLocalizedString("Not set", comment: "Unset playlist time")
    }

    private func mediaType(_ value: Int) -> String {
        switch value {
        case 1: return NSLocalizedString("Audio", comment: "Playlist media type")
        case 2: return NSLocalizedString("Video", comment: "Playlist media type")
        default:
            return String(format: NSLocalizedString("Unknown (%@)", comment: "Unknown playlist media type value"),
                          String(value))
        }
    }
}

struct PlaylistConflictRow: Identifiable {
    let field: PlaylistChangedField
    let value: String
    var id: PlaylistChangedField { field }
}

struct PlaylistConflictPresentation {
    let fields: [PlaylistChangedField]

    static var invalidMetadata: GeneralError {
        .general(message: NSLocalizedString("Unable to display this playlist conflict. Please update Library Merger.",
                                           comment: "Unknown or invalid conflict metadata"))
    }

    init(changedFieldsJSON: String, model: Model) throws {
        do {
            let fields = try JSONDecoder().decode([PlaylistChangedField].self, from: Data(changedFieldsJSON.utf8))
            guard !fields.isEmpty, Set(fields).count == fields.count else { throw Self.invalidMetadata }
            for field in fields { _ = try field.value(in: model) }
            self.fields = fields
        } catch {
            throw Self.invalidMetadata
        }
    }

    var question: String {
        fields.count == 1 ? fields[0].question : "Which settings should this item use?"
    }

    var choosesWholeVersion: Bool { fields.count > 1 }

    func rows(for model: Model) throws -> [PlaylistConflictRow] {
        try fields.map { PlaylistConflictRow(field: $0, value: try $0.value(in: model)) }
    }
}

struct PlaylistChangedDetails: View {
    let presentation: PlaylistConflictPresentation?
    let model: Model

    var body: some View {
        VStack(alignment: .leading) {
            if let presentation = presentation, let rows = try? presentation.rows(for: model) {
                ForEach(rows) { row in
                    PlaylistValue(key: row.field.title, value: row.value)
                }
            } else {
                Text("Unable to display this playlist conflict. Please update Library Merger.")
                    .foregroundColor(.red)
            }
        }
    }
}
