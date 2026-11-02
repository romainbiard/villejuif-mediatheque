// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Bokeh document type (`type.code`), distinguishing physical from online.
public struct DocumentKind: Hashable, Sendable, Codable {
    public let code: String
    public let label: String

    public init(code: String, label: String) {
        self.code = code
        self.label = label
    }

    /// Codes of resources available online (harvested by Bokeh or Eurêka).
    public static let digitalCodes: Set<String> = ["ArteVod", "Cafeyn", "Numilog", "ToutApprendre", "23", "24", "26", "27"]

    public var isDigital: Bool { Self.digitalCodes.contains(code) }
    public var searchFacet: String { "T\(code)" }

    public static let book = DocumentKind(code: "1", label: "Livre")
    public static let cd = DocumentKind(code: "3", label: "CD")
    public static let dvd = DocumentKind(code: "4", label: "DVD")
    public static let audiobook = DocumentKind(code: "17", label: "Livre audio")
}

public struct Notice: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let authors: [String]
    public let year: String?
    public let publisher: String?
    public let kind: DocumentKind
    public let coverURL: URL?
    public let series: String?
    public let volume: String?
    public let permalink: URL?
    /// Copies as harvested overnight: useful for the call number and the library,
    /// not for availability (see `CatalogClient.copies`).
    public let harvestedCopies: [HarvestedCopy]

    public init(
        id: Int, title: String, authors: [String], year: String?, publisher: String?,
        kind: DocumentKind, coverURL: URL?, series: String?, volume: String?, permalink: URL?,
        harvestedCopies: [HarvestedCopy]
    ) {
        self.id = id
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

    /// Libraries that own a copy, without duplicates, in network order.
    public var libraries: [Library] {
        let owned = Set(harvestedCopies.compactMap(\.library))
        return Library.allCases.filter(owned.contains)
    }
}

public struct HarvestedCopy: Hashable, Sendable, Codable {
    public let library: Library?
}

public struct SearchPage: Sendable, Equatable, Codable {
    public let total: Int
    public let documents: [Notice]

    public init(total: Int, documents: [Notice]) {
        self.total = total
        self.documents = documents
    }
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

/// Real-time availability of a copy.
public enum CopyStatus: Hashable, Sendable {
    case available
    case onLoan(dueDate: Date?)
    /// "En réserve", "À demander à l'accueil".
    case onRequest
    case other(String)

    public var isAvailable: Bool {
        switch self {
        case .available, .onRequest: true
        case .onLoan, .other: false
        }
    }
}

/// A copy seen in real time (`noticeajax/exemplaires`).
public struct LiveCopy: Hashable, Sendable {
    public let library: Library?
    public let libraryName: String
    public let status: CopyStatus
    public let statusLabel: String
    public let section: String?
    public let shelfMark: String?
    public let holdCount: Int
}

/// Availability badge for a record in a results list.
public struct Availability: Hashable, Sendable, Codable {
    public let label: String
    public let isAvailable: Bool
}
