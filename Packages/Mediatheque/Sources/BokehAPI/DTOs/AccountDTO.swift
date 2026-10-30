import Foundation

/// `GET /api/user/account`, accessible avec le seul cookie de session.
public struct AccountResponseDTO: Decodable, Sendable {
    public let account: AccountDTO
}

public struct AccountDTO: Decodable, Sendable {
    public struct Identity: Decodable, Sendable {
        public let firstName: String
        public let lastName: String
        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct Contact: Decodable, Sendable {
        public let email: String
        public let phone: String
        public let mobile: String
        public let address: String
        public let zipCode: String
        public let city: String
        enum CodingKeys: String, CodingKey {
            case email, phone, mobile, address, city
            case zipCode = "zip_code"
        }
    }

    public struct Card: Decodable, Sendable {
        public let id: String
        public let expireAt: String
        public let expired: Bool
        public let aboutToExpire: Bool
        public let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case id, expired
            case expireAt = "expire_at"
            case aboutToExpire = "about_to_expire"
            case expiresIn = "expires_in"
        }
    }

    public struct LibraryDetails: Decodable, Sendable {
        public let id: Int
        public let label: String
        public let code: String
    }

    public struct Permissions: Decodable, Sendable {
        public let blocked: Bool
        public let loanForbidden: Bool
        public let holdForbidden: Bool
        public let digitalResourcesForbidden: Bool
        enum CodingKeys: String, CodingKey {
            case blocked
            case loanForbidden = "loan_forbidden"
            case holdForbidden = "hold_forbidden"
            case digitalResourcesForbidden = "digital_resources_forbidden"
        }
    }

    public struct Counters: Decodable, Sendable {
        public let loans: Int
        public let lateLoans: Int
        public let holds: Int
        public let digitalLoans: Int
        public let debts: Int
        public let waitingToBePulled: Int
        enum CodingKeys: String, CodingKey {
            case loans, holds, debts
            case lateLoans = "late_loans"
            case digitalLoans = "pnb_loans"
            case waitingToBePulled = "waiting_to_be_pulled"
        }
    }

    public struct Message: Decodable, Sendable {
        public let content: String
        public let unread: Bool
    }

    public let label: String
    public let login: String
    public let identity: Identity
    public let contact: Contact
    public let card: Card
    public let libraryDetails: LibraryDetails
    public let permissions: Permissions
    public let counters: Counters
    public let message: Message

    enum CodingKeys: String, CodingKey {
        case label, login, identity, contact, card, permissions, counters, message
        case libraryDetails = "library_details"
    }
}

/// `GET /api/user/loans` et `/api/user/loans/history`.
public struct LoansResponseDTO: Decodable, Sendable {
    public let loans: [LoanDTO]
}

public struct RecordRefDTO: Decodable, Sendable {
    public let id: Int
    public let thumbnail: String?
}

public struct LoanDTO: Decodable, Sendable {
    /// `{idAbonné}_{idPrêt}`, réutilisable tel quel pour `prolongerPret`.
    public let id: String
    public let title: String
    public let author: String
    public let dateDue: String
    public let library: String
    public let record: RecordRefDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, author, library, record
        case dateDue = "date_due"
    }
}

/// `GET /api/user/holds`. Le rang n'y figure pas (seulement dans le HTML du compte).
public struct HoldsResponseDTO: Decodable, Sendable {
    public let holds: [HoldDTO]
}

public struct HoldDTO: Decodable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    /// Texte libre, par exemple « Pas disponible avant le 14/11/2026 ».
    public let status: String
    /// Lieu de retrait.
    public let library: String
    public let record: RecordRefDTO?
}

/// Réponse JSON des popups AJAX (réservation…).
public struct PopupDTO: Decodable, Sendable {
    public let result: String
    public let title: String?
    public let content: String
}
