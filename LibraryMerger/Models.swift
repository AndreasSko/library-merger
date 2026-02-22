//
//  Models.swift
//  LibraryMerger
//
//  Created by Andreas Skorczyk on 09.11.20.
//

import Foundation

struct Related: Decodable {
    let blockRange: [BlockRange]?
    let bookmark: Bookmark?
    let inputField: InputField?
    let location: Location?
    let publicationLocation: Location?
    let note: Note?
    let tag: Tag?
    let tagMap: TagMap?
    let userMark: UserMark?
    let userMarkBlockRange: UserMarkBlockRange?
}

enum Model: Decodable {
    enum CodingKeys: String, CodingKey {
        case modelType = "type"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modelType = try container.decode(String.self, forKey: .modelType)
        switch modelType {
        case "BlockRange":
            let mdl = try BlockRange(from: decoder)
            self = .blockRange(mdl)
        case "Bookmark":
            let mdl = try Bookmark(from: decoder)
            self = .bookmark(mdl)
        case "InputField":
            let mdl = try InputField(from: decoder)
            self = .inputField(mdl)
        case "Location":
            let mdl = try Location(from: decoder)
            self = .location(mdl)
        case "Note":
            let mdl = try Note(from: decoder)
            self = .note(mdl)
        case "Tag":
            let mdl = try Tag(from: decoder)
            self = .tag(mdl)
        case "TagMap":
            let mdl = try TagMap(from: decoder)
            self = .tagMap(mdl)
        case "UserMark":
            let mdl = try UserMark(from: decoder)
            self = .userMark(mdl)
        case "UserMarkBlockRange":
            let mdl = try UserMarkBlockRange(from: decoder)
            self = .userMarkBlockRange(mdl)
        default:
            fatalError()
        }
    }

    case blockRange(BlockRange)
    case bookmark(Bookmark)
    case inputField(InputField)
    case location(Location)
    case note(Note)
    case tag(Tag)
    case tagMap(TagMap)
    case userMark(UserMark)
    case userMarkBlockRange(UserMarkBlockRange)
}

struct BlockRange: Decodable {
    let blockRangeId: Int
    let blockType: Int
    let identifier: Int
    let startToken: NullInt32
    let endToken: NullInt32
    let userMarkId: Int
}

struct Bookmark: Decodable {
    let bookmarkId: Int
    let locationId: Int
    let publicationLocationId: Int
    let slot: Int
    let title: String
    let snippet: NullString
    let blockType: Int
    let blockIdentifier: NullInt32
}

struct InputField: Decodable {
    let locationId: Int
    let textTag: String
    let value: String
}

struct Location: Decodable {
    let locationId: Int
    let bookNumber: NullInt32
    let chapterNumber: NullInt32
    let documentId: NullInt32
    let track: NullInt32
    let issueTagNumber: Int
    let keySymbol: NullString
    let mepsLanguage: NullInt32
    let locationType: Int
    let title: NullString
}

struct Note: Decodable {
    let noteId: Int
    let guid: String
    let userMarkId: NullInt32
    let locationId: NullInt32
    let title: NullString
    let content: NullString
    let lastModified: String
    let blockType: Int
    let blockIdentifier: NullInt32
}

struct Tag: Decodable {
    let tagId: Int
    let tagType: Int
    let name: String
    let imageFilename: NullString
}

struct TagMap: Decodable {
    let tagMapId: Int
    let playlistItemId: NullInt32
    let locationId: NullInt32
    let noteId: NullInt32
    let tagId: Int
    let position: Int
}

struct UserMark: Decodable {
    let userMarkId: Int
    let colorIndex: Int
    let locationId: Int
    let styleIndex: Int
    let userMarkGuid: String
    let version: Int
}

struct UserMarkBlockRange: Decodable {
    let userMark: UserMark
    let blockRanges: [BlockRange]
}

struct NullInt32: Decodable {
    enum CodingKeys: String, CodingKey {
        case int32 = "Int32"
        case valid = "Valid"
    }

    let int32: Int
    let valid: Bool
}

struct NullString: Decodable {
    enum CodingKeys: String, CodingKey {
        case string = "String"
        case valid = "Valid"
    }

    let string: String
    let valid: Bool
}
