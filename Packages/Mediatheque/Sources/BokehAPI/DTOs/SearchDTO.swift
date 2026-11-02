// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Response from `recherche/simple/.../format/json`, modeled on the JSON received.
public struct SearchResponseDTO: Decodable, Sendable {
    public let total: Int
    public let records: [RecordDTO]

    enum CodingKeys: String, CodingKey {
        case total, records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        records = try container.decodeIfPresent([RecordDTO].self, forKey: .records) ?? []
    }
}

public struct RecordDTO: Decodable, Sendable {
    public struct DocumentType: Decodable, Sendable {
        public let code: String
        public let label: String
    }

    public let titles: [String]
    public let serial: String?
    public let volume: String?
    public let creators: [String]
    public let date: String
    public let publishers: [String]
    public let type: DocumentType
    public let thumbnail: String?
    public let permalink: String
    public let items: [ItemDTO]

    enum CodingKeys: String, CodingKey {
        case titles, serial, volume, creators, date, publishers, type, thumbnail, permalink, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        titles = try container.decodeIfPresent([String].self, forKey: .titles) ?? []
        serial = try container.decodeIfPresent(String.self, forKey: .serial)
        volume = try container.decodeLenientString(forKey: .volume)
        creators = try container.decodeIfPresent([String].self, forKey: .creators) ?? []
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        publishers = try container.decodeIfPresent([String].self, forKey: .publishers) ?? []
        type = try container.decode(DocumentType.self, forKey: .type)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        permalink = try container.decode(String.self, forKey: .permalink)
        items = try container.decodeIfPresent([ItemDTO].self, forKey: .items) ?? []
    }

    /// Numeric identifier of the record, read from the permalink (`/id/474169`).
    public var noticeID: Int? {
        permalink.split(separator: "/").last.flatMap { Int($0) }
    }
}

public struct ItemDTO: Decodable, Sendable {
    public struct Subfield: Decodable, Sendable {
        public let code: String
        public let valeur: String
    }

    public let annex: String?
    public let shelfMark: String
    public let activity: String
    /// Field 995 of the copy; `false` in the JSON for digital resources.
    public let zone995: [Subfield]

    enum CodingKeys: String, CodingKey {
        case zone995
        case annex = "annexe"
        case shelfMark = "cote"
        case activity = "activite"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annex = try container.decodeLenientString(forKey: .annex)
        shelfMark = try container.decodeIfPresent(String.self, forKey: .shelfMark) ?? ""
        activity = try container.decodeIfPresent(String.self, forKey: .activity) ?? ""
        zone995 = (try? container.decode([Subfield].self, forKey: .zone995)) ?? []
    }

    public func subfield(_ code: String) -> String? {
        zone995.first { $0.code == code }?.valeur
    }
}

// MARK: - Lenient decoding (Bokeh mixes numbers and strings)

extension KeyedDecodingContainer {
    func decodeLenientString(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return String(int) }
        return nil
    }
}
