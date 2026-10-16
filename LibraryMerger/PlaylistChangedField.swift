import Foundation

// The playlist settings Go reports as differing in a conflict. Only these are
// shown, so the user doesn't have to compare unchanged settings.
enum PlaylistChangedField: String, Decodable, CaseIterable, Identifiable {
    case label, startTrimOffsetTicks, endTrimOffsetTicks, accuracy, endAction
    case baseDurationTicks, majorMultimediaType, durationTicks

    var id: Self { self }

    var title: String {
        switch self {
        case .label: return NSLocalizedString("Name:", comment: "Playlist field")
        case .startTrimOffsetTicks: return NSLocalizedString("Start trim:", comment: "Playlist field")
        case .endTrimOffsetTicks: return NSLocalizedString("End trim:", comment: "Playlist field")
        case .accuracy: return NSLocalizedString("Accuracy:", comment: "Playlist field")
        case .endAction: return NSLocalizedString("End action:", comment: "Playlist field")
        case .baseDurationTicks, .durationTicks: return NSLocalizedString("Duration:", comment: "Playlist field")
        case .majorMultimediaType: return NSLocalizedString("Media type:", comment: "Playlist field")
        }
    }

    var question: String {
        switch self {
        case .label:
            return NSLocalizedString("What should this item be called?", comment: "Playlist conflict question")
        case .startTrimOffsetTicks:
            return NSLocalizedString("Where should playback start?", comment: "Playlist conflict question")
        case .endTrimOffsetTicks:
            return NSLocalizedString("Where should playback stop?", comment: "Playlist conflict question")
        case .accuracy:
            return NSLocalizedString("Which timing accuracy should be used?", comment: "Playlist conflict question")
        case .endAction:
            return NSLocalizedString("What should happen when this item finishes?",
                                     comment: "Playlist conflict question")
        case .baseDurationTicks, .durationTicks:
            return NSLocalizedString("How long should this item play?", comment: "Playlist conflict question")
        case .majorMultimediaType:
            return NSLocalizedString("Which media type should be used?", comment: "Playlist conflict question")
        }
    }

    // Returns nil if the field doesn't belong to the given model.
    func value(in model: Model) -> String? {
        switch (model, self) {
        case (.playlistItem(let item), .label): return item.label
        case (.playlistItem(let item), .startTrimOffsetTicks): return formatTicks(item.startTrimOffsetTicks)
        case (.playlistItem(let item), .endTrimOffsetTicks): return formatTicks(item.endTrimOffsetTicks)
        case (.playlistItem(let item), .accuracy): return String(item.accuracy)
        case (.playlistItem(let item), .endAction): return endAction(item.endAction)
        case (.playlistItemLocationMap(let mapping), .baseDurationTicks): return formatTicks(mapping.baseDurationTicks)
        case (.playlistItemLocationMap(let mapping), .majorMultimediaType):
            return mediaType(mapping.majorMultimediaType)
        case (.playlistItemIndependentMediaMap(let mapping), .durationTicks): return formatTicks(mapping.durationTicks)
        default: return nil
        }
    }

    private func formatTicks(_ ticks: NullInt64) -> String {
        ticks.valid ? formatTicks(ticks.int64) : NSLocalizedString("Not set", comment: "Unset playlist time")
    }

    // A tick is 100 nanoseconds. Show all digits, so two different values never look the same.
    private func formatTicks(_ ticks: Int64) -> String {
        let seconds = Double(ticks) / 10_000_000
        return seconds.formatted(.number.precision(.fractionLength(0...7))) + " s"
    }

    private func endAction(_ value: Int) -> String {
        switch value {
        case 0: return NSLocalizedString("Play next", comment: "Playlist end action")
        case 1: return NSLocalizedString("Stop", comment: "Playlist end action")
        case 2: return NSLocalizedString("Freeze frame", comment: "Playlist end action")
        case 3: return NSLocalizedString("Repeat", comment: "Playlist end action")
        default: return String(value)
        }
    }

    private func mediaType(_ value: Int) -> String {
        switch value {
        case 1: return NSLocalizedString("Audio", comment: "Playlist media type")
        case 2: return NSLocalizedString("Video", comment: "Playlist media type")
        default: return String(value)
        }
    }
}
