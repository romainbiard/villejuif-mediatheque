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
        enum CodingKeys: String, CodingKey { case id, label }
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
        enum CodingKeys: String, CodingKey { case content, unread }
    }

    public struct Preferences: Decodable, Sendable {
        /// Subscribed newsletters. The format of an item has never been seen (empty list):
        /// we only read how many there are.
        public let newsletters: [Opaque]
        enum CodingKeys: String, CodingKey { case newsletters }
    }

    /// Card linked to the account. Its `id` is the patron identifier for the `/abonne/...` routes.
    public struct LinkedCard: Decodable, Sendable {
        public let id: Int
    }

    /// Any JSON value, ignored.
    public struct Opaque: Decodable, Sendable {
        public init(from decoder: any Decoder) throws {}
    }

    /// The card number: the only field the account can't do without.
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

// Decoding lives in extensions so the memberwise initialisers stay available for the empty values.

extension AccountDTO {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let login = try container.decodeLenientString(forKey: .login), !login.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .login, in: container, debugDescription: "No card number")
        }
        self.login = login
        identity = container.lenientObject(Identity.self, forKey: .identity) ?? Identity(firstName: "", lastName: "", nickname: nil)
        contact = container.lenientObject(Contact.self, forKey: .contact)
            ?? Contact(email: "", phone: "", mobile: "", address: "", zipCode: "", city: "")
        card = container.lenientObject(Card.self, forKey: .card) ?? Card(expireAt: "", expired: false, aboutToExpire: false, expiresIn: 0)
        libraryDetails = container.lenientObject(LibraryDetails.self, forKey: .libraryDetails) ?? LibraryDetails(id: 0, label: "")
        permissions = container.lenientObject(Permissions.self, forKey: .permissions)
            ?? Permissions(holdForbidden: false, digitalResourcesForbidden: false)
        counters = container.lenientObject(Counters.self, forKey: .counters) ?? Counters(loans: 0, lateLoans: 0, waitingToBePulled: 0)
        message = container.lenientObject(Message.self, forKey: .message) ?? Message(content: "", unread: false)
        preferences = container.lenientObject(Preferences.self, forKey: .preferences)
        cards = container.contains(.cards) ? container.lossyList(of: LinkedCard.self, forKey: .cards) : nil
    }
}

extension AccountDTO.Identity {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstName = container.lenientText(forKey: .firstName)
        lastName = container.lenientText(forKey: .lastName)
        nickname = try container.decodeLenientString(forKey: .nickname)
    }
}

extension AccountDTO.Contact {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = container.lenientText(forKey: .email)
        phone = container.lenientText(forKey: .phone)
        mobile = container.lenientText(forKey: .mobile)
        address = container.lenientText(forKey: .address)
        zipCode = container.lenientText(forKey: .zipCode)
        city = container.lenientText(forKey: .city)
    }
}

extension AccountDTO.Card {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expireAt = container.lenientText(forKey: .expireAt)
        expired = container.lenientFlag(forKey: .expired)
        aboutToExpire = container.lenientFlag(forKey: .aboutToExpire)
        expiresIn = container.lenientCount(forKey: .expiresIn)
    }
}

extension AccountDTO.LibraryDetails {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenientCount(forKey: .id)
        label = container.lenientText(forKey: .label)
    }
}

extension AccountDTO.Permissions {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holdForbidden = container.lenientFlag(forKey: .holdForbidden)
        digitalResourcesForbidden = container.lenientFlag(forKey: .digitalResourcesForbidden)
    }
}

extension AccountDTO.Counters {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loans = container.lenientCount(forKey: .loans)
        lateLoans = container.lenientCount(forKey: .lateLoans)
        waitingToBePulled = container.lenientCount(forKey: .waitingToBePulled)
    }
}

extension AccountDTO.Message {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = container.lenientText(forKey: .content)
        unread = container.lenientFlag(forKey: .unread)
    }
}

extension AccountDTO.Preferences {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newsletters = container.lossyList(of: AccountDTO.Opaque.self, forKey: .newsletters)
    }
}

/// `GET /api/user/loans` and `/api/user/loans/history`.
public struct LoansResponseDTO: Decodable, Sendable {
    public let loans: [LoanDTO]
    enum CodingKeys: String, CodingKey { case loans }

    public init(from decoder: any Decoder) throws {
        loans = try decoder.container(keyedBy: CodingKeys.self).lossyList(of: LoanDTO.self, forKey: .loans)
    }
}

public struct RecordRefDTO: Decodable, Sendable {
    public let id: Int
    public let thumbnail: String?
}

public struct LoanDTO: Decodable, Sendable {
    /// `{idAbonné}_{idPrêt}`, reusable as is for `prolongerPret`. Strict: a loan without one is skipped.
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = container.lenientText(forKey: .title)
        author = container.lenientText(forKey: .author)
        dateDue = container.lenientText(forKey: .dateDue)
        library = container.lenientText(forKey: .library)
        record = container.lenientObject(RecordRefDTO.self, forKey: .record)
    }
}

/// `GET /api/user/holds`. The queue position isn't included (only in the account HTML).
public struct HoldsResponseDTO: Decodable, Sendable {
    public let holds: [HoldDTO]
    enum CodingKeys: String, CodingKey { case holds }

    public init(from decoder: any Decoder) throws {
        holds = try decoder.container(keyedBy: CodingKeys.self).lossyList(of: HoldDTO.self, forKey: .holds)
    }
}

public struct HoldDTO: Decodable, Sendable {
    /// Needed to cancel the hold. Strict: a hold without one is skipped.
    public let id: String
    public let title: String
    /// Free text, e.g. "Pas disponible avant le 14/11/2026". `null` for some holds (seen in November 2026).
    public let status: String?
    /// Pickup location.
    public let library: String
    public let record: RecordRefDTO?

    enum CodingKeys: String, CodingKey { case id, title, status, library, record }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = container.lenientText(forKey: .title)
        status = try container.decodeLenientString(forKey: .status)
        library = container.lenientText(forKey: .library)
        record = container.lenientObject(RecordRefDTO.self, forKey: .record)
    }
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
