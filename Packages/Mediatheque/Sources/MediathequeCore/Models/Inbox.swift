import Foundation

/// Une entrée du centre de notifications (la cloche de Mon compte).
/// Le site n'a pas d'API de notifications : tout est déduit des prêts, des réservations
/// et du message de la médiathèque, puis gardé sur l'appareil.
public struct InboxItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case loanDueSoon, loanLate, holdReady, libraryMessage
    }

    /// Stable d'une synchronisation à l'autre : c'est ce qui évite les doublons.
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let date: Date
    public var isRead: Bool
    /// Prêt concerné, pour « Prolonger » depuis la liste.
    public let loanID: Loan.ID?

    public init(id: String, kind: Kind, title: String, body: String, date: Date, isRead: Bool = false, loanID: Loan.ID? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.date = date
        self.isRead = isRead
        self.loanID = loanID
    }
}

public struct Inbox: Codable, Hashable, Sendable {
    public private(set) var items: [InboxItem]

    /// Durée de conservation de l'historique sur l'appareil.
    public static let retentionDays = 30

    public init(items: [InboxItem] = []) {
        self.items = items
    }

    public var unreadCount: Int { items.count { !$0.isRead } }

    /// Ajoute les nouvelles entrées (non lues), garde l'état lu des anciennes et oublie celles de plus de 30 jours.
    /// Renvoie les entrées ajoutées.
    @discardableResult
    public mutating func merge(_ fresh: [InboxItem], now: Date, calendar: Calendar) -> [InboxItem] {
        let known = Set(items.map(\.id))
        let added = fresh.filter { !known.contains($0.id) }
        let limit = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) ?? now
        items = (items + added)
            .filter { $0.date >= limit }
            .sorted { $0.date > $1.date }
        return added
    }

    public mutating func markRead(_ id: InboxItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
    }

    public mutating func markAllRead() {
        for index in items.indices { items[index].isRead = true }
    }
}

public enum InboxPlanner {
    /// Entrées déduites du compte : retours proches ou en retard, réservations arrivées.
    public static func items(for snapshot: AccountSnapshot, daysBefore: Int, now: Date, calendar: Calendar) -> [InboxItem] {
        let today = calendar.startOfDay(for: now)
        let french = Locale(identifier: "fr_FR")
        var items: [InboxItem] = []

        for loan in snapshot.loans {
            let due = calendar.startOfDay(for: loan.dueDate)
            let dueKey = Int(due.timeIntervalSince1970)
            let dueText = due.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french))
            switch loan.dueState(now: now, calendar: calendar) {
            case .late:
                items.append(InboxItem(
                    id: "late-\(loan.id)-\(dueKey)",
                    kind: .loanLate,
                    title: "« \(loan.title) » est en retard",
                    body: "À rendre depuis le \(dueText). Rapportez-le ou essayez de le prolonger.",
                    date: calendar.date(byAdding: .day, value: 1, to: due) ?? due,
                    loanID: loan.id
                ))
            case let .dueSoon(days) where days <= daysBefore:
                // Daté du jour où le rappel aurait dû partir, jamais dans le futur.
                let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: due) ?? today
                items.append(InboxItem(
                    id: "due-\(loan.id)-\(dueKey)",
                    kind: .loanDueSoon,
                    title: days == 0 ? "« \(loan.title) » est à rendre aujourd'hui" : "« \(loan.title) » est à rendre \(days == 1 ? "demain" : "dans \(days) jours")",
                    body: "Retour prévu le \(dueText) à \(loan.library?.shortName ?? loan.libraryName).",
                    date: min(max(reminderDay, today), now),
                    loanID: loan.id
                ))
            default:
                break
            }
        }

        for hold in snapshot.holds where hold.isReadyForPickup {
            items.append(InboxItem(
                id: "hold-\(hold.id)",
                kind: .holdReady,
                title: "« \(hold.title) » vous attend",
                body: "À retirer à \(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName). \(hold.statusText)",
                date: now
            ))
        }
        return items
    }

    /// Message affiché par la médiathèque sur le compte (`account.message`).
    public static func libraryMessage(_ text: String, now: Date) -> InboxItem {
        InboxItem(
            id: "message-\(stableHash(text))",
            kind: .libraryMessage,
            title: "Message de la médiathèque",
            body: text.replacing(#/<[^>]+>/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            date: now
        )
    }

    /// `hashValue` change à chaque lancement : on prend un hachage FNV-1a, stable.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
