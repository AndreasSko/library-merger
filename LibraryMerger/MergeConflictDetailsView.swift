//
//  MergeConflictView.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 28.10.20.
//

import SwiftUI
import Gomobile

struct MergeConflictDetailsView: View {
    var conflict: MergeConflict?
    var side: MergeSide
    var markingText = MarkingText()

    var body: some View {
        VStack(alignment: .leading) {
            if let conflict = conflict,
               let sideData = side == .leftSide ? conflict.left : conflict.right {
                Text(side == .leftSide ? "Left backup" : "Right backup")
                    .font(.caption)
                    .foregroundColor(.secondary)
                switch sideData.model {
                case .bookmark(let bookmark):
                    BookmarkDetail(bookmark: bookmark)
                case .userMarkBlockRange(let umbr):
                    UserMarkBlockRangeDetail(umbr: umbr, other: otherMarking(conflict), text: markingText)
                case .note(let note):
                    NoteDetail(note: note)
                case .inputField(let inputfield):
                    InputFieldDetail(inputField: inputfield)
                case .playlistItem, .playlistItemLocationMap, .playlistItemIndependentMediaMap:
                    PlaylistDetail(changedFields: conflict.changedFields, model: sideData.model)
                default:
                    Text("Error! Can not generate preview")
                        .foregroundColor(.red)
                }
            } else {
                Text("Error! Can not generate preview")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 0.1), lineWidth: 1)
        )
        .shadow(color: Color.gray.opacity(0.2), radius: 20)
        .contentShape(Rectangle())
    }

    private func otherMarking(_ conflict: MergeConflict) -> UserMarkBlockRange? {
        guard case .userMarkBlockRange(let other) = (side == .leftSide ? conflict.right : conflict.left)?.model else {
            return nil
        }
        return other
    }
}

struct MergeConflictView_Previews: PreviewProvider {
    static var previews: some View {
        MergeConflictDetailsView(conflict: nil, side: .leftSide)
    }
}

struct BookmarkDetail: View {
    var bookmark: Bookmark

    var body: some View {
            HStack {
            VStack(alignment: .leading) {
                KeyValue(key: "Title:", value: bookmark.title)

                if bookmark.snippet.valid && bookmark.snippet.string != "" {
                    KeyValue(key: "Snippet:", value: bookmark.snippet.string)
                }

                if bookmark.blockIdentifier.valid {
                    KeyValue(key: "Paragraph:",
                             value: String(bookmark.blockIdentifier.int32))
                }
            }
            Spacer()
        }
    }
}

struct NoteDetail: View {
    var note: Note

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if note.title.valid {
                    KeyValue(key: "Title:", value: note.title.string)
                }

                if note.content.valid {
                    KeyValue(key: "Content:", value: note.content.string)
                }

                KeyValue(key: "Last Modified:",
                         value: formatDate(note.lastModified))
            }
            Spacer()
        }
    }

    func formatDate(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        let parsed = parser.date(from: dateString) ?? Date()

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        return String(formatter.string(from: parsed))
    }
}

struct UserMarkBlockRangeDetail: View {
    var umbr: UserMarkBlockRange
    // The marking on the other side, to show where the two overlap
    var other: UserMarkBlockRange?
    var text = MarkingText()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.enabled, let snippets = text.snippets, !snippets.isEmpty {
                ForEach(snippets.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(place(of: snippets[index]))
                            Spacer()
                            if index == 0 {
                                Button(action: text.hide, label: { Image(systemName: "eye.slash") })
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text("Hide text"))
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        ParagraphScroller(text: highlighted(snippets[index]),
                                          marked: markedRanges(snippets, index),
                                          link: text.link, onTap: text.select)
                            .accessibilityValue(Text("Marked: \(snippets[index].marked)"))
                    }
                }
            } else {
                ForEach(umbr.blockRanges.filter { $0.startToken.valid && $0.endToken.valid },
                        id: \.blockRangeId) { blockRange in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(words(of: blockRange))
                            Spacer()
                            if text.loading && text.downloaded > 0 {
                                Text(downloadSize)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)

                        WordShapes(blockRange: blockRange, other: overlapping(blockRange), color: markingColor,
                                   loading: text.loading,
                                   progress: text.total > 0 ? Double(text.downloaded) / Double(text.total) : nil)
                    }
                }

                if let reason = text.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if text.available && (!text.enabled || text.canRetry) {
                    Button(action: text.load, label: {
                        Label(text.canRetry ? "Try again" : "Load text from jw.org",
                              systemImage: text.canRetry ? "arrow.clockwise" : "quote.opening")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 1))
                    })
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityIdentifier("load-marking-text")
                }
            }
        }
    }

    private var downloadSize: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: text.downloaded, countStyle: .file)
        guard text.total > 0 else { return downloaded }
        return String.localizedStringWithFormat(NSLocalizedString("%@ of %@", comment: "Download size"), downloaded,
                                                ByteCountFormatter.string(fromByteCount: text.total, countStyle: .file))
    }

    // words tells which words a block range marks, like "Words 10–14". Before the text is
    // loaded, only the position of the words is known, not the paragraph number.
    private func words(of blockRange: BlockRange) -> String {
        let start = Int(blockRange.startToken.int32) + 1, end = Int(blockRange.endToken.int32) + 1
        // Block type 2 is a Bible verse
        if blockRange.blockType == 2 {
            return String.localizedStringWithFormat(NSLocalizedString("Verse %d · words %d–%d", comment: ""),
                                                    blockRange.identifier, start, end)
        }
        return String.localizedStringWithFormat(NSLocalizedString("Words %d–%d", comment: ""), start, end)
    }

    private func overlapping(_ blockRange: BlockRange) -> BlockRange? {
        other?.blockRanges.first { $0.blockType == blockRange.blockType && $0.identifier == blockRange.identifier }
    }

    // place tells where a paragraph is, like "Paragraph 2 · Subheading"
    private func place(of snippet: MarkingSnippet) -> String {
        var parts: [String] = []
        if let verse = snippet.verse, verse > 0 {
            parts.append(String.localizedStringWithFormat(NSLocalizedString("Verse %d", comment: ""), verse))
        }
        if let number = snippet.number, number > 0 {
            parts.append(String.localizedStringWithFormat(NSLocalizedString("Paragraph %d", comment: ""), number))
        }
        if let heading = snippet.heading, !heading.isEmpty {
            parts.append(heading)
        }
        return parts.joined(separator: " · ")
    }

    private var markingColor: Color {
        markingColors[umbr.userMark.colorIndex] ?? Color(red: 1.00, green: 1, blue: 1)
    }

    // markedRanges returns where this side and, in the same paragraph, the other side mark text
    private func markedRanges(_ snippets: [MarkingSnippet], _ index: Int) -> [NSRange] {
        let range = { (snippet: MarkingSnippet) in
            NSRange(location: snippet.before.utf16.count, length: snippet.marked.utf16.count)
        }
        let own = snippets[index]
        guard let other = text.otherSnippets?.first(where: {
            $0.before + $0.marked + $0.after == own.before + own.marked + own.after
        }) else {
            return [range(own)]
        }
        return [range(own), range(other)]
    }

    private func highlighted(_ snippet: MarkingSnippet) -> NSAttributedString {
        // The paragraph is set in New York, Apple's serif, so it reads like a page of the publication
        let body = UIFont.preferredFont(forTextStyle: .body)
        let font = body.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 0) } ?? body
        let text = NSMutableAttributedString(string: snippet.before + snippet.marked + snippet.after,
                                             attributes: [.font: font, .foregroundColor: UIColor.label])
        // JW Library highlights with the marking color at half opacity
        text.addAttribute(.backgroundColor, value: UIColor(markingColor).withAlphaComponent(0.5),
                          range: NSRange(location: snippet.before.utf16.count, length: snippet.marked.utf16.count))
        return text
    }

    // The colors of the JW Library marking palette
    let markingColors: [Int: Color] = [
        1: Color(red: 0.99, green: 0.94, blue: 0.38),
        2: Color(red: 0.79, green: 0.91, blue: 0.67),
        3: Color(red: 0.71, green: 0.87, blue: 0.99),
        4: Color(red: 0.94, green: 0.69, blue: 0.78),
        5: Color(red: 0.98, green: 0.79, blue: 0.64),
        6: Color(red: 0.78, green: 0.73, blue: 0.89)
    ]
}

struct InputFieldDetail: View {
    var inputField: InputField

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                KeyValue(key: "TextTag:", value: inputField.textTag)

                Text("Value:").bold()
                switch inputField.value {
                case "0":
                    Image(systemName: "square")
                case "1":
                    Image(systemName: "checkmark.square")
                default:
                    Text(inputField.value)
                        .padding(.bottom, 0.5)
                }
            }
            Spacer()
        }
    }
}

struct KeyValue: View {
    var key: String
    var value: String

    var body: some View {
        Text(NSLocalizedString(key, comment: "String")).bold()
        Text(value)
            .padding(.bottom, 0.5)
    }
}

// https://www.objc.io/blog/2020/03/05/swiftui-alignment-guides/
struct CustomAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        return context[.leading]
    }
}
extension HorizontalAlignment {
    static let custom: HorizontalAlignment = HorizontalAlignment(CustomAlignment.self)
}

struct PlaylistOverview: View {
    var itemLabel: String?
    var related: Related?
    var publication: Publication?
    var sourceURL: String?
    var thumbnail: UIImage?

    private var title: String? {
        if let title = related?.location?.title, title.valid, !title.string.isEmpty {
            return title.string
        }
        return itemLabel
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 192, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }
            if let title = title {
                KeyValue(key: "Title:", value: title)
            }
            if let publication = publication {
                KeyValue(key: "Publication:", value: publication.title)
                if !publication.issueTitle.isEmpty {
                    KeyValue(key: "Issue:", value: publication.issueTitle)
                }
            }
            if let media = related?.independentMedia, media.originalFilename != title {
                KeyValue(key: "Media:", value: media.originalFilename)
            }
            if let tag = related?.tag {
                KeyValue(key: "Playlist:", value: tag.name)
            }
            if let sourceURL = sourceURL, let url = URL(string: sourceURL) {
                Link("Open on jw.org", destination: url)
            }
        }
        .padding(.horizontal)
    }
}

struct PlaylistDetail: View {
    var changedFields: [PlaylistChangedField]
    var model: Model

    var body: some View {
        // Fall back to all settings of the item if Go reported none as changed.
        let fields = changedFields.isEmpty ? PlaylistChangedField.allCases : changedFields
        VStack(alignment: .leading) {
            ForEach(fields) { field in
                if let value = field.value(in: model) {
                    KeyValue(key: field.title, value: value)
                }
            }
        }
    }
}
