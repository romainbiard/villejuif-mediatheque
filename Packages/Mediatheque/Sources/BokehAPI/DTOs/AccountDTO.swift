// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// `GET /api/user/account`, accessible with the session cookie alone.
public struct AccountResponseDTO: Decodable, Sendable {
    public let account: AccountDTO
}

public struct AccountDTO: Decodable, Sendable {
    public struct Identity: Decodable, Sendable {
        public let firstName: String
        public let lastName: String
        public let nickname: String?
        enum CodingKeys: String, CodingKey {
            case nickname
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
        public let expireAt: String
        public let expired: Bool
        public let aboutToExpire: Bool
        public let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case expired
            case expireAt = "expire_at"
            case aboutToExpire = "about_to_expire"
            case expiresIn = "expires_in"
        }
    }

    public struct LibraryDetails: Decodable, Sendable {
        public let id: Int
        public let label: String
    }

    public struct Permissions: Decodable, Sendable {
        public let holdForbidden: Bool
        public let digitalResourcesForbidden: Bool
        enum CodingKeys: String, CodingKey {
            case holdForbidden = "hold_forbidden"
            case digitalResourcesForbidden = "digital_resources_forbidden"
        }
    }

    public struct Counters: Decodable, Sendable {
        public let loans: Int
        public let lateLoans: Int
        public let waitingToBePulled: Int
        enum CodingKeys: String, CodingKey {
            case loans
            case lateLoans = "late_loans"
            case waitingToBePulled = "waiting_to_be_pulled"
        }
    }

    public struct Message: Decodable, Sendable {
        public let content: String
        public let unread: Bool
    }

    public struct Preferences: Decodable, Sendable {
        /// Subscribed newsletters. The format of an item has never been seen (empty list):
        /// we only read how many there are.
        public let newsletters: [Opaque]
    }

    /// Card linked to the account. Its `id` is the patron identifier for the `/abonne/...` routes.
    public struct LinkedCard: Decodable, Sendable {
        public let id: Int
    }

    /// Any JSON value, ignored.
    public struct Opaque: Decodable, Sendable {
        public init(from decoder: any Decoder) throws {}
    }

    public let login: String
    public let identity: Identity
    public let contact: Contact
    public let card: Card
    public let libraryDetails: LibraryDetails
    public let permissions: Permissions
    public let counters: Counters
    public let message: Message
    public let preferences: Preferences?
    public let cards: [LinkedCard]?

    enum CodingKeys: String, CodingKey {
        case login, identity, contact, card, permissions, counters, message, preferences, cards
        case libraryDetails = "library_details"
    }
}

/// `GET /api/user/loans` and `/api/user/loans/history`.
public struct LoansResponseDTO: Decodable, Sendable {
    public let loans: [LoanDTO]
}

public struct RecordRefDTO: Decodable, Sendable {
    public let id: Int
    public let thumbnail: String?
}

public struct LoanDTO: Decodable, Sendable {
    /// `{idAbonné}_{idPrêt}`, reusable as is for `prolongerPret`.
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

/// `GET /api/user/holds`. The queue position isn't included (only in the account HTML).
public struct HoldsResponseDTO: Decodable, Sendable {
    public let holds: [HoldDTO]
}

public struct HoldDTO: Decodable, Sendable {
    public let id: String
    public let title: String
    /// Free text, e.g. "Pas disponible avant le 14/11/2026".
    public let status: String
    /// Pickup location.
    public let library: String
    public let record: RecordRefDTO?
}

/// Answer to a default-selection toggle: the site's new link, "supprimer…" once added, "ajouter…" once removed.
public struct SelectionToggleDTO: Decodable, Sendable {
    public let anchor: String

    public var holdsRecord: Bool { anchor.contains("supprimer-de-la-selection") }
}

/// JSON response from AJAX popups (holds…).
public struct PopupDTO: Decodable, Sendable {
    public let title: String?
    public let content: String
}
