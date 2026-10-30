import Foundation

/// Réponse de `recherche/simple/.../format/json`, calquée sur le JSON reçu.
public struct SearchResponseDTO: Decodable, Sendable {
    public let total: Int
    public let pageSize: Int
    public let page: Int
    public let records: [RecordDTO]

    enum CodingKeys: String, CodingKey {
        case total, page, records
        case pageSize = "page_size"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? 10
        // `page` vaut 1 (nombre) en page 1, puis "2" (chaîne) ensuite.
        page = try container.decodeLenientInt(forKey: .page) ?? 1
        records = try container.decodeIfPresent([RecordDTO].self, forKey: .records) ?? []
    }
}

public struct RecordDTO: Decodable, Sendable {
    public struct DocumentType: Decodable, Sendable {
        public let code: String
        public let label: String
    }

    public let identifier: String
    public let titles: [String]
    public let serial: String?
    public let volume: String?
    public let creators: [String]
    public let date: String
    public let publishers: [String]
    public let language: String?
    public let type: DocumentType
    public let thumbnail: String?
    public let permalink: String
    public let collections: [String]
    public let items: [ItemDTO]

    enum CodingKeys: String, CodingKey {
        case identifier, titles, serial, volume, creators, date, publishers, language, type, thumbnail, permalink, collections, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        titles = try container.decodeIfPresent([String].self, forKey: .titles) ?? []
        serial = try container.decodeIfPresent(String.self, forKey: .serial)
        volume = try container.decodeLenientString(forKey: .volume)
        creators = try container.decodeIfPresent([String].self, forKey: .creators) ?? []
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        publishers = try container.decodeIfPresent([String].self, forKey: .publishers) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language)
        type = try container.decode(DocumentType.self, forKey: .type)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        permalink = try container.decode(String.self, forKey: .permalink)
        collections = try container.decodeIfPresent([String].self, forKey: .collections) ?? []
        items = try container.decodeIfPresent([ItemDTO].self, forKey: .items) ?? []
    }

    /// Identifiant numérique de la notice, lu dans le permalien (`/id/474169`).
    public var noticeID: Int? {
        permalink.split(separator: "/").last.flatMap { Int($0) }
    }
}

public struct ItemDTO: Decodable, Sendable {
    public struct Subfield: Decodable, Sendable {
        public let code: String
        public let valeur: String
    }

    public let id: Int
    public let noticeID: Int
    public let barcode: String?
    public let annex: String?
    public let shelfMark: String
    public let activity: String
    public let libraryID: Int
    /// Zone 995 de l'exemplaire ; `false` dans le JSON pour les ressources numériques.
    public let zone995: [Subfield]

    enum CodingKeys: String, CodingKey {
        case id, zone995
        case noticeID = "id_notice"
        case barcode = "code_barres"
        case annex = "annexe"
        case shelfMark = "cote"
        case activity = "activite"
        case libraryID = "id_bib"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id) ?? 0
        noticeID = try container.decodeLenientInt(forKey: .noticeID) ?? 0
        barcode = try container.decodeLenientString(forKey: .barcode)
        annex = try container.decodeLenientString(forKey: .annex)
        shelfMark = try container.decodeIfPresent(String.self, forKey: .shelfMark) ?? ""
        activity = try container.decodeIfPresent(String.self, forKey: .activity) ?? ""
        libraryID = try container.decodeLenientInt(forKey: .libraryID) ?? 0
        zone995 = (try? container.decode([Subfield].self, forKey: .zone995)) ?? []
    }

    public func subfield(_ code: String) -> String? {
        zone995.first { $0.code == code }?.valeur
    }
}

// MARK: - Décodage tolérant (Bokeh mélange nombres et chaînes)

extension KeyedDecodingContainer {
    func decodeLenientInt(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let string = try? decodeIfPresent(String.self, forKey: key) { return Int(string) }
        return nil
    }

    func decodeLenientString(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return String(int) }
        return nil
    }
}
