//
//  MergeConflictOverview.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 10.11.20.
//

import SwiftUI
import Gomobile

struct MergeConflictOverview: View {
    var mrt: ModelRelatedTuple?

    var body: some View {
        VStack {
            let related = mrt?.related
            let publication = lookupPublicationFor(related?.location)

            switch mrt?.model {
            case .bookmark(let bookmark):
                BookmarkOverview(bookmark: bookmark, related: related, publication: publication)
            case .userMarkBlockRange(let umbr):
                UserMarkBlockRangeOverview(umbr: umbr, related: related, publication: publication)
            case .note(let note):
                NoteOverview(note: note, related: related, publication: publication)
            case .inputField(let inputField):
                InputFieldOverview(inputField: inputField, related: related, publication: publication)
            default:
                Text("An error occurred")
            }
        }
    }
}

struct BookmarkOverview: View {
    var bookmark: Bookmark
    var related: Related?
    var publication: Publication?

    var body: some View {
        VStack(alignment: .custom) {
            if publication != nil {
                HStack {
                    Text("Publication:").bold()
                    Text(publication?.shortTitle ?? "")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)

                if publication?.issueTitle != "" {
                    HStack {
                        Text("Issue:").bold()
                        Text(publication?.issueTitle ?? "")
                            .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                            .alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 0.5)
                }
            } else if related?.publicationLocation?.keySymbol.valid ?? false {
                HStack {
                    Text("Publication:").bold()
                    Text(related?.publicationLocation?.keySymbol.string ?? "")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            HStack(alignment: .top) {
                Text("Slot:").bold()
                HStack {
                    Text("\(bookmark.slot)")
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(bookmarkColors[bookmark.slot])

                }
                .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                .alignmentGuide(.custom) { $0[.leading] }
            }
        }
    }

    let bookmarkColors: [Int: Color] = [
        0: Color(red: 0.64, green: 0.24, blue: 0.40),
        1: Color(red: 0.48, green: 0.40, blue: 0.60),
        2: Color(red: 0.39, green: 0.51, blue: 0.69),
        3: Color(red: 0.12, green: 0.74, blue: 0.73),
        4: Color(red: 0.25, green: 0.57, blue: 0.38),
        5: Color(red: 0.33, green: 0.78, blue: 0.46),
        6: Color(red: 0.81, green: 0.83, blue: 0.52),
        7: Color(red: 0.86, green: 0.52, blue: 0.33),
        8: Color(red: 0.86, green: 0.39, blue: 0.30),
        9: Color(red: 0.62, green: 0.40, blue: 0.26)
    ]
}

struct NoteOverview: View {
    var note: Note
    var related: Related?
    var publication: Publication?

    var body: some View {
        VStack(alignment: .custom) {

            if publication != nil {
                HStack {
                    Text("Publication:").bold()
                    Text(publication?.shortTitle ?? "")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)

                if publication?.issueTitle != "" {
                    HStack {
                        Text("Issue:").bold()
                        Text(publication?.issueTitle ?? "")
                            .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                            .alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 0.5)
                }
            }

            if publication == nil && related?.location?.keySymbol.valid ?? false {
                HStack {
                    Text("Publication:").bold()
                    Text("\(related?.location?.keySymbol.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if publication == nil && related?.location?.documentId.valid ?? false {
                HStack {
                    Text("Document ID:").bold()
                    Text(String(related?.location?.documentId.int32 ?? -1))
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.track.valid ?? false {
                HStack {
                    Text("Track:").bold()
                    Text("\(related?.location?.track.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.title.valid ?? false {
                HStack {
                    Text("Title:").bold()
                    Text("\(related?.location?.title.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.bookNumber.valid ?? false {
                HStack {
                    Text("Book ID:").bold()
                    Text("\(related?.location?.bookNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.chapterNumber.valid ?? false {
                HStack {
                    Text("Chapter:").bold()
                    Text("\(related?.location?.chapterNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }
        }
    }
}

struct UserMarkBlockRangeOverview: View {
    var umbr: UserMarkBlockRange
    var related: Related?
    var publication: Publication?

    var body: some View {
        VStack(alignment: .custom) {

            if publication != nil {
                HStack {
                    Text("Publication:").bold()
                    Text(publication?.shortTitle ?? "")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)

                if publication?.issueTitle != "" {
                    HStack {
                        Text("Issue:").bold()
                        Text(publication?.issueTitle ?? "")
                            .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                            .alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 0.5)
                }
            }

            if publication == nil && related?.location?.keySymbol.valid ?? false {
                HStack {
                    Text("Publication:").bold()
                    Text("\(related?.location?.keySymbol.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if publication == nil && related?.location?.documentId.valid ?? false {
                HStack {
                    Text("Document ID:").bold()
                    Text(String(related?.location?.documentId.int32 ?? -1))
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.track.valid ?? false {
                HStack {
                    Text("Track:").bold()
                    Text("\(related?.location?.track.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.title.valid ?? false {
                HStack {
                    Text("Title:").bold()
                    Text("\(related?.location?.title.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.bookNumber.valid ?? false {
                HStack {
                    Text("Book ID:").bold()
                    Text("\(related?.location?.bookNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.chapterNumber.valid ?? false {
                HStack {
                    Text("Chapter:").bold()
                    Text("\(related?.location?.chapterNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

        }
    }
}

struct InputFieldOverview: View {
    var inputField: InputField
    var related: Related?
    var publication: Publication?

    var body: some View {
        VStack(alignment: .custom) {

            if publication != nil {
                HStack {
                    Text("Publication:").bold()
                    Text(publication?.shortTitle ?? "")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)

                if publication?.issueTitle != "" {
                    HStack {
                        Text("Issue:").bold()
                        Text(publication?.issueTitle ?? "")
                            .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                            .alignmentGuide(.custom) { $0[.leading] }
                    }
                    .padding(.bottom, 0.5)
                }
            }

            if publication == nil && related?.location?.keySymbol.valid ?? false {
                HStack {
                    Text("Publication:").bold()
                    Text("\(related?.location?.keySymbol.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if publication == nil && related?.location?.documentId.valid ?? false {
                HStack {
                    Text("Document ID:").bold()
                    Text(String(related?.location?.documentId.int32 ?? -1))
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.track.valid ?? false {
                HStack {
                    Text("Track:").bold()
                    Text("\(related?.location?.track.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.title.valid ?? false {
                HStack {
                    Text("Title:").bold()
                    Text("\(related?.location?.title.string ?? "")")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.bookNumber.valid ?? false {
                HStack {
                    Text("Book ID:").bold()
                    Text("\(related?.location?.bookNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

            if related?.location?.chapterNumber.valid ?? false {
                HStack {
                    Text("Chapter:").bold()
                    Text("\(related?.location?.chapterNumber.int32 ?? -1)")
                        .frame(width: UIScreen.main.bounds.size.width-138, alignment: .leading)
                        .alignmentGuide(.custom) { $0[.leading] }
                }
                .padding(.bottom, 0.5)
            }

        }
    }
}

struct MergeConflictOverview_Previews: PreviewProvider {
    static var previews: some View {
        MergeConflictOverview(mrt: nil)
    }
}
