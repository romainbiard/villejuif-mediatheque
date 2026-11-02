// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// An entry in the notification center (the bell in Mon compte).
/// The site has no notifications API: everything is derived from loans, holds
/// and the library's message, then kept on the device.
public struct InboxItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case loanDueSoon, loanLate, holdReady, libraryMessage
    }

    /// Stable from one sync to the next: this is what prevents duplicates.
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let date: Date
    public var isRead: Bool
    /// Related loan, for "Prolonger" from the list.
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

    /// How long the history is kept on the device.
    public static let retentionDays = 30

    public init(items: [InboxItem] = []) {
        self.items = items
    }

    public var unreadCount: Int { items.count { !$0.isRead } }

    /// Adds new entries (unread), keeps the read state of older ones and drops those older than 30 days.
    /// Returns the added entries.
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
    /// Entries derived from the account: upcoming or overdue returns, holds ready.
    public static func items(for snapshot: AccountSnapshot, daysBefore: Int, now: Date, calendar: Calendar) -> [InboxItem] {
        let today = calendar.startOfDay(for: now)
        var items: [InboxItem] = []

        for loan in snapshot.loans {
            let due = calendar.startOfDay(for: loan.dueDate)
            let dueKey = Int(due.timeIntervalSince1970)
            let dueText = due.formatted(.dateTime.weekday(.wide).day().month(.wide))
            switch loan.dueState(now: now, calendar: calendar) {
            case .late:
                items.append(InboxItem(
                    id: "late-\(loan.id)-\(dueKey)",
                    kind: .loanLate,
                    title: .local("« \(loan.title) » est en retard"),
                    body: .local("À rendre depuis le \(dueText). Rapportez-le ou essayez de le prolonger."),
                    date: calendar.date(byAdding: .day, value: 1, to: due) ?? due,
                    loanID: loan.id
                ))
            case let .dueSoon(days) where days <= daysBefore:
                // Dated to the day the reminder should have fired, never in the future.
                let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: due) ?? today
                items.append(InboxItem(
                    id: "due-\(loan.id)-\(dueKey)",
                    kind: .loanDueSoon,
                    title: days == 0 ? .local("« \(loan.title) » est à rendre aujourd'hui")
                        : days == 1 ? .local("« \(loan.title) » est à rendre demain")
                        : .local("« \(loan.title) » est à rendre dans \(days) jours"),
                    body: .local("Retour prévu le \(dueText) à \(loan.library?.shortName ?? loan.libraryName)."),
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
                title: .local("« \(hold.title) » vous attend"),
                body: .local("À retirer à \(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName). \(hold.statusText)"),
                date: now
            ))
        }
        return items
    }

    /// Message shown by the library on the account (`account.message`).
    public static func libraryMessage(_ text: String, now: Date) -> InboxItem {
        InboxItem(
            id: "message-\(stableHash(text))",
            kind: .libraryMessage,
            title: .local("Message de la médiathèque"),
            body: text.replacing(#/<[^>]+>/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            date: now
        )
    }

    /// `hashValue` changes on every launch: we use a stable FNV-1a hash.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
