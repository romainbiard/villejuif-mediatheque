import Foundation

/// Type de document Bokeh (`type.code`), avec la distinction physique / en ligne.
public struct DocumentKind: Hashable, Sendable, Codable {
    public let code: String
    public let label: String

    public init(code: String, label: String) {
        self.code = code
        self.label = label
    }

    /// Codes des ressources consultables en ligne (moissonnées par Bokeh ou Eurêka).
    public static let digitalCodes: Set<String> = ["ArteVod", "Cafeyn", "Numilog", "ToutApprendre", "23", "24", "26", "27"]

    public var isDigital: Bool { Self.digitalCodes.contains(code) }
    public var searchFacet: String { "T\(code)" }

    public static let book = DocumentKind(code: "1", label: "Livre")
    public static let magazine = DocumentKind(code: "2", label: "Revue")
    public static let cd = DocumentKind(code: "3", label: "CD")
    public static let dvd = DocumentKind(code: "4", label: "DVD")
    public static let audiobook = DocumentKind(code: "17", label: "Livre audio")
    public static let boardGame = DocumentKind(code: "15", label: "Jeu de société")
}

public struct Notice: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    /// Clé Bokeh (`identifier`), nécessaire pour la page notice.
    public let key: String
    public let title: String
    public let authors: [String]
    public let year: String?
    public let publisher: String?
    public let kind: DocumentKind
    public let coverURL: URL?
    public let series: String?
    public let volume: String?
    public let permalink: URL?
    /// Exemplaires tels que moissonnés la nuit : utiles pour la cote et la médiathèque,
    /// pas pour la disponibilité (voir `CatalogClient.copies`).
    public let harvestedCopies: [HarvestedCopy]

    public init(
        id: Int, key: String, title: String, authors: [String], year: String?, publisher: String?,
        kind: DocumentKind, coverURL: URL?, series: String?, volume: String?, permalink: URL?,
        harvestedCopies: [HarvestedCopy]
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.authors = authors
        self.year = year
        self.publisher = publisher
        self.kind = kind
        self.coverURL = coverURL
        self.series = series
        self.volume = volume
        self.permalink = permalink
        self.harvestedCopies = harvestedCopies
    }

    /// Médiathèques qui possèdent un exemplaire, sans doublon, dans l'ordre du réseau.
    public var libraries: [Library] {
        let owned = Set(harvestedCopies.compactMap(\.library))
        return Library.allCases.filter(owned.contains)
    }
}

public struct HarvestedCopy: Hashable, Sendable, Codable {
    public let library: Library?
    public let shelfMark: String
    public let barcode: String?
}

public struct SearchPage: Sendable, Equatable, Codable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let documents: [Notice]

    public init(total: Int, page: Int, pageSize: Int, documents: [Notice]) {
        self.total = total
        self.page = page
        self.pageSize = pageSize
        self.documents = documents
    }

    public var hasNextPage: Bool { page * pageSize < total }
}

public struct SearchQuery: Hashable, Sendable {
    public enum Sort: String, Hashable, Sendable {
        case relevance = "*"
        case newest = "date_creation desc"
    }

    public var text: String
    public var kinds: [DocumentKind]
    public var libraries: [Library]
    public var sort: Sort
    public var page: Int

    public init(text: String, kinds: [DocumentKind] = [], libraries: [Library] = [], sort: Sort = .relevance, page: Int = 1) {
        self.text = text
        self.kinds = kinds
        self.libraries = libraries
        self.sort = sort
        self.page = page
    }

    var facets: [String] { kinds.map(\.searchFacet) + libraries.map(\.searchFacet) }
}

/// Disponibilité en temps réel d'un exemplaire.
public enum CopyStatus: Hashable, Sendable {
    case available
    case onLoan(dueDate: Date?)
    /// « En réserve », « À demander à l'accueil ».
    case onRequest
    case other(String)

    public var isAvailable: Bool {
        switch self {
        case .available, .onRequest: true
        case .onLoan, .other: false
        }
    }
}

/// Un exemplaire vu en temps réel (`noticeajax/exemplaires`).
public struct LiveCopy: Hashable, Sendable {
    public let library: Library?
    public let libraryName: String
    public let status: CopyStatus
    public let statusLabel: String
    public let section: String?
    public let location: String?
    public let shelfMark: String?
    public let holdCount: Int
    /// Lien du formulaire de retrait si l'exemplaire est réservable.
    public let pickupPath: String?
}

/// Badge de disponibilité d'une notice dans une liste de résultats.
public struct Availability: Hashable, Sendable, Codable {
    public let label: String
    public let isAvailable: Bool
}
