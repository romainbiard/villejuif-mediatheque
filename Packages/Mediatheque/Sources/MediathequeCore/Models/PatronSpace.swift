// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// A patron's wish list ("panier" on the Bokeh side).
public struct Selection: Identifiable, Hashable, Sendable {
    public let id: Int
    public let basketID: Int?
    public let name: String
    public let count: Int
    public let updatedAt: Date?
    public let coverURLs: [URL]

    public init(id: Int, basketID: Int?, name: String, count: Int, updatedAt: Date?, coverURLs: [URL]) {
        self.id = id
        self.basketID = basketID
        self.name = name
        self.count = count
        self.updatedAt = updatedAt
        self.coverURLs = coverURLs
    }

    /// The three selections the site creates for each patron.
    public static let defaultNames = ["Mes préférés", "Déjà lu", "À lire"]
    public var isDefault: Bool { Self.defaultNames.contains(name) }
}

/// A borrowed document the patron can rate.
public struct RecordToRate: Identifiable, Hashable, Sendable {
    public let recordID: Int
    public let recordKey: String
    public let title: String
    public let author: String?
    public let coverURL: URL?
    public var id: Int { recordID }

    public init(recordID: Int, recordKey: String, title: String, author: String?, coverURL: URL?) {
        self.recordID = recordID
        self.recordKey = recordKey
        self.title = title
        self.author = author
        self.coverURL = coverURL
    }
}

public struct Review: Identifiable, Hashable, Sendable {
    public let id: String
    public let recordID: Int?
    public let title: String
    public let text: String
    public let rating: Int?

    public init(id: String, recordID: Int?, title: String, text: String, rating: Int?) {
        self.id = id
        self.recordID = recordID
        self.title = title
        self.text = text
        self.rating = rating
    }
}

public struct Suggestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?

    public init(id: String, title: String, detail: String?) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Purchase suggestion to send (`suggestion-achat-add` form).
public struct SuggestionDraft: Hashable, Sendable {
    public var kind: SuggestionKind = .book
    public var title = ""
    public var author = ""
    public var isbn = ""
    public var comment = ""

    public init() {}

    /// Title and author are required by the site.
    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !author.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Types offered by the form, the site's `DocType` codes (the most common ones).
public enum SuggestionKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case book = "1"
    case largePrint = "19"
    case audiobook = "17"
    case comic = "BD"
    case cd = "3"
    case dvd = "4"
    case boardGame = "15"
    case languageMethod = "21"
    case ebook = "Numilog"

    public var id: String { rawValue }

    /// Comics have no type of their own on the site: we send them as a book, noted in the comment.
    public var docTypeCode: String { self == .comic ? SuggestionKind.book.rawValue : rawValue }

    public var label: String {
        switch self {
        case .book: .local("Livre")
        case .largePrint: .local("Livre en gros caractères")
        case .audiobook: .local("Livre audio")
        case .comic: .local("Bande dessinée")
        case .cd: "CD"
        case .dvd: "DVD"
        case .boardGame: .local("Jeu de société")
        case .languageMethod: .local("Méthode de langue")
        case .ebook: .local("Livre numérique")
        }
    }
}

/// Contact details editable online (`modifier` form). Name and address are changed at the front desk.
public struct ContactDetails: Hashable, Sendable {
    public var nickname: String
    public var email: String
    public var phone: String
    public var channel: SendingChannel

    public init(nickname: String, email: String, phone: String, channel: SendingChannel) {
        self.nickname = nickname
        self.email = email
        self.phone = phone
        self.channel = channel
    }
}

/// The site's `favoriteSendingChannel`.
public enum SendingChannel: String, CaseIterable, Hashable, Sendable, Identifiable {
    case any = "0"
    case email = "1"
    case sms = "2"
    case letter = "3"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .any: .local("Indifférent")
        case .email: .local("Courriel")
        case .sms: "SMS"
        case .letter: .local("Courrier")
        }
    }
}

public enum ProfileError: Error, Equatable, Sendable {
    /// The site rejected the form, with its message.
    case rejected(String)
    case missingPatronID
}
