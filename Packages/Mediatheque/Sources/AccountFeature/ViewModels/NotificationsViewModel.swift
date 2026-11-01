// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Notification center: the local history, grouped by day, with "Prolonger" on returns.
@MainActor
@Observable
public final class NotificationsViewModel {
    public struct Section: Identifiable, Equatable {
        public enum Kind: Sendable { case today, thisWeek, earlier }
        public let kind: Kind
        public let items: [InboxItem]
        public var id: Kind { kind }

        public var title: String {
            switch kind {
            case .today: "Aujourd'hui"
            case .thisWeek: "Cette semaine"
            case .earlier: "Plus tôt"
            }
        }
    }

    public private(set) var inbox = Inbox()
    public private(set) var renewing: Set<Loan.ID> = []
    /// Loans renewed from this screen: the button disappears.
    public private(set) var renewed: Set<Loan.ID> = []
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.inboxClient) private var inboxClient
    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored private let calendar = Calendar.paris

    public init() {}

    public func load() {
        inbox = inboxClient.load()
    }

    public var sections: [Section] {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let grouped = Dictionary(grouping: inbox.items) { item -> Section.Kind in
            if item.date >= today { return .today }
            if item.date >= weekStart { return .thisWeek }
            return .earlier
        }
        return [Section.Kind.today, .thisWeek, .earlier].compactMap { kind in
            grouped[kind].map { Section(kind: kind, items: $0.sorted { $0.date > $1.date }) }
        }
    }

    public func markRead(_ item: InboxItem) {
        guard !item.isRead else { return }
        inbox.markRead(item.id)
        inboxClient.save(inbox)
    }

    public func markAllRead() {
        guard inbox.unreadCount > 0 else { return }
        inbox.markAllRead()
        inboxClient.save(inbox)
        feedback = .lightImpact
    }

    /// True if the entry carries a loan that can still be renewed.
    public func canRenew(_ item: InboxItem) -> Bool {
        guard let loanID = item.loanID else { return false }
        return !renewed.contains(loanID)
    }

    public func renew(_ item: InboxItem) async {
        guard let loanID = item.loanID, !renewing.contains(loanID) else { return }
        renewing.insert(loanID)
        defer { renewing.remove(loanID) }
        do {
            switch try await account.renew([loanID]).first {
            case let .renewed(_, newDueDate):
                renewed.insert(loanID)
                markRead(item)
                message = "Prolongé jusqu'au \(newDueDate.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))"
                feedback = .success
                // New due date: reminders and history brought up to date.
                _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
                load()
            case .refused, nil:
                renewed.insert(loanID)
                message = "Ce prêt ne peut pas être prolongé"
                feedback = .error
            }
        } catch {
            message = LoadError(error) == .offline ? "Prolongation impossible hors ligne" : "La prolongation n'a pas abouti"
            feedback = .error
        }
    }

    public func dismissMessage() { message = nil }
}
