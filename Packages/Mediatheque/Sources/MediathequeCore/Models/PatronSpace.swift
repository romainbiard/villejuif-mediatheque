import Foundation

/// Une liste d'envies de l'abonné (« panier » côté Bokeh).
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

    /// Les trois sélections créées par le site pour chaque abonné.
    public static let defaultNames = ["Mes préférés", "Déjà lu", "À lire"]
    public var isDefault: Bool { Self.defaultNames.contains(name) }
}

/// Un document emprunté que l'abonné peut noter.
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

/// Suggestion d'achat à envoyer (formulaire `suggestion-achat-add`).
public struct SuggestionDraft: Hashable, Sendable {
    public var kind: SuggestionKind = .book
    public var title = ""
    public var author = ""
    public var isbn = ""
    public var comment = ""

    public init() {}

    /// Titre et auteur sont obligatoires côté site.
    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !author.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Types proposés par le formulaire, codes `DocType` du site (les plus courants).
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

    /// La BD n'a pas de type propre sur le site : on l'envoie comme un livre, précisé en commentaire.
    public var docTypeCode: String { self == .comic ? SuggestionKind.book.rawValue : rawValue }

    public var label: String {
        switch self {
        case .book: "Livre"
        case .largePrint: "Livre en gros caractères"
        case .audiobook: "Livre audio"
        case .comic: "Bande dessinée"
        case .cd: "CD"
        case .dvd: "DVD"
        case .boardGame: "Jeu de société"
        case .languageMethod: "Méthode de langue"
        case .ebook: "Livre numérique"
        }
    }
}

/// Coordonnées modifiables en ligne (formulaire `modifier`). Le nom et l'adresse se changent à l'accueil.
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

/// `favoriteSendingChannel` du site.
public enum SendingChannel: String, CaseIterable, Hashable, Sendable, Identifiable {
    case any = "0"
    case email = "1"
    case sms = "2"
    case letter = "3"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .any: "Indifférent"
        case .email: "Courriel"
        case .sms: "SMS"
        case .letter: "Courrier"
        }
    }
}

public enum ProfileError: Error, Equatable, Sendable {
    /// Le site a refusé le formulaire, avec son message.
    case rejected(String)
    case missingPatronID
}
