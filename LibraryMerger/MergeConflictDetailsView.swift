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

    var body: some View {
        VStack(alignment: .leading) {
            if let conflict = conflict,
               let sideData = side == .leftSide ? conflict.left : conflict.right {
                switch sideData.model {
                case .bookmark(let bookmark):
                    BookmarkDetail(bookmark: bookmark)
                case .userMarkBlockRange(let umbr):
                    UserMarkBlockRangeDetail(umbr: umbr)
                case .note(let note):
                    NoteDetail(note: note)
                case .inputField(let inputfield):
                    InputFieldDetail(inputField: inputfield)
                default:
                    Text("Error! Can not generate preview")
                        .foregroundColor(.red)
                }
            } else {
                Text("Error! Can not generate preview")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity)
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

    var body: some View {
        VStack(alignment: .custom) {
            HStack {
                Text("Color:").bold()
                Circle()
                    .fill(markingColors[umbr.userMark.colorIndex] ?? Color(red: 1.00, green: 1, blue: 1))
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.custom) { $0[.leading] }
            }
            .padding(.bottom, 2.0)

            ForEach(umbr.blockRanges, id: \.blockRangeId) { blockRange in
                HStack {
                    Text("Identifier:").bold()
                    Text("\(blockRange.identifier)").alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)

                if blockRange.startToken.valid {
                    HStack {
                        Text("Start token:").bold()
                        Text("\(blockRange.startToken.int32)").alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 0.5)
                }

                if blockRange.endToken.valid {
                    HStack {
                        Text("End token:").bold()
                        Text("\(blockRange.endToken.int32)").alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 2.0)
                }
            }
        }
    }

    let markingColors: [Int: Color] = [
        1: Color(red: 1.00, green: 0.93, blue: 0.23),
        2: Color(red: 0.62, green: 0.98, blue: 0.32),
        3: Color(red: 0.16, green: 0.71, blue: 0.96),
        4: Color(red: 1.00, green: 0.63, blue: 0.78),
        5: Color(red: 1.00, green: 0.73, blue: 0.46),
        6: Color(red: 0.68, green: 0.52, blue: 1.00)
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
