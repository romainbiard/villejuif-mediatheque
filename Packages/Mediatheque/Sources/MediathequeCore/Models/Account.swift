import Foundation

public struct Patron: Hashable, Sendable {
    public struct Permissions: Hashable, Sendable {
        public let blocked: Bool
        public let loanForbidden: Bool
        public let holdForbidden: Bool
        public let digitalResourcesForbidden: Bool
    }

    public struct Counters: Hashable, Sendable {
        public let loans: Int
        public let lateLoans: Int
        public let holds: Int
        public let digitalLoans: Int
        public let debts: Int
        /// Réservations arrivées, à retirer.
        public let waitingToBePulled: Int
    }

    public let cardNumber: String
    public let firstName: String
    public let lastName: String
    public let email: String?
    public let phone: String?
    public let homeLibrary: Library?
    public let cardExpiry: Date?
    public let cardExpired: Bool
    public let cardAboutToExpire: Bool
    public let cardExpiresInDays: Int
    public let permissions: Permissions
    public let counters: Counters
    /// Message de la médiathèque, s'il y en a un.
    public let message: String?
    public let hasUnreadMessage: Bool

    public var displayName: String { "\(firstName) \(lastName.capitalized)" }
}

public struct Loan: Identifiable, Hashable, Sendable, Codable {
    /// `{idAbonné}_{idPrêt}`.
    public let id: String
    public let title: String
    public let author: String
    public let dueDate: Date
    public let library: Library?
    public let libraryName: String
    public let recordID: Int?
    public let coverURL: URL?

    public init(
        id: String, title: String, author: String, dueDate: Date, library: Library?,
        libraryName: String, recordID: Int?, coverURL: URL?
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.dueDate = dueDate
        self.library = library
        self.libraryName = libraryName
        self.recordID = recordID
        self.coverURL = coverURL
    }

    /// Identifiant de l'abonné, préfixe de l'identifiant du prêt (utile pour les routes HTML).
    public var patronID: String { String(id.split(separator: "_").first ?? "") }

    public enum DueState: Hashable, Sendable {
        case late(days: Int)
        case dueSoon(days: Int)
        case onTime(days: Int)
    }

    /// État par rapport à `now`, avec « bientôt » à 7 jours ou moins.
    public func dueState(now: Date, calendar: Calendar) -> DueState {
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        if days < 0 { return .late(days: -days) }
        if days <= 7 { return .dueSoon(days: days) }
        return .onTime(days: days)
    }
}

public struct Hold: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let author: String
    /// Texte du site, par exemple « Pas disponible avant le 14/11/2026 ».
    public let statusText: String
    public let pickupLibrary: Library?
    public let pickupLibraryName: String
    public let recordID: Int?
    public let coverURL: URL?
    /// Rang dans la file, lu dans le HTML du compte (absent de l'API).
    public var rank: Int?

    /// Date lue dans le statut « Pas disponible avant le … ».
    public var expectedDate: Date? { BokehDates.firstDate(in: statusText) }

    /// Vrai quand le document attend l'abonné.
    public var isReadyForPickup: Bool {
        let status = statusText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return status.contains("disponible") && !status.contains("pas disponible")
            || status.contains("a retirer") || status.contains("en attente de retrait")
    }
}

public enum RenewalResult: Hashable, Sendable {
    case renewed(loanID: Loan.ID, newDueDate: Date)
    case refused(loanID: Loan.ID)
}
