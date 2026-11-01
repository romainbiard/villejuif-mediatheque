// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Account home: the record (counters, card) refreshes on every appearance.
@MainActor
@Observable
public final class AccountHomeViewModel {
    public private(set) var isRefreshing = false
    public private(set) var error: LoadError?
    /// Bell badge.
    public private(set) var unreadNotifications = 0

    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.inboxClient) private var inbox

    public init() {}

    public func refresh(_ session: SessionStore) async {
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshUnreadCount()
        }
        do {
            let patron = try await account.patron()
            session.update(patron)
            error = nil
            // Snapshot for the widget and offline use, reminders rescheduled, notification center updated.
            withDependencies(from: self) { AccountSync.record(libraryMessage: patron.message) }
            _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        } catch {
            let loadError = LoadError(error)
            if loadError == .notLoggedIn { await session.logout() }
            self.error = loadError
        }
    }

    public func refreshUnreadCount() {
        unreadNotifications = inbox.load().unreadCount
    }
}

@MainActor
@Observable
public final class LoansViewModel {
    public struct Section: Identifiable, Equatable {
        public enum Kind: String, Sendable { case late, thisWeek, later }
        public let kind: Kind
        public let loans: [Loan]
        public var id: Kind { kind }

        public var title: String {
            switch kind {
            case .late: "En retard"
            case .thisWeek: "Cette semaine"
            case .later: "Plus tard"
            }
        }
    }

    public private(set) var state: LoadState<[Loan]> = .idle
    public private(set) var renewing: Set<Loan.ID> = []
    /// Loans the site refused to renew during this screen session.
    public private(set) var refused: Set<Loan.ID> = []
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored private let calendar = Calendar.paris

    public init() {}

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await account.loans().sorted { $0.dueDate < $1.dueDate })
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public var sections: [Section] {
        let loans = state.value ?? []
        let grouped = Dictionary(grouping: loans) { loan -> Section.Kind in
            switch loan.dueState(now: now, calendar: calendar) {
            case .late: .late
            case .dueSoon: .thisWeek
            case .onTime: .later
            }
        }
        return [Section.Kind.late, .thisWeek, .later].compactMap { kind in
            grouped[kind].map { Section(kind: kind, loans: $0) }
        }
    }

    public func dueState(of loan: Loan) -> Loan.DueState {
        loan.dueState(now: now, calendar: calendar)
    }

    public func renew(_ loan: Loan) async {
        await renew([loan.id])
    }

    public func renewAll() async {
        await renew((state.value ?? []).map(\.id).filter { !refused.contains($0) })
    }

    private func renew(_ ids: [Loan.ID]) async {
        guard !ids.isEmpty else { return }
        renewing.formUnion(ids)
        defer { renewing.subtract(ids) }
        do {
            let results = try await account.renew(ids)
            var renewedCount = 0
            for result in results {
                switch result {
                case .renewed: renewedCount += 1
                case let .refused(id): refused.insert(id)
                }
            }
            let refusedCount = results.count - renewedCount
            switch (renewedCount, refusedCount) {
            case (_, 0):
                message = renewedCount > 1 ? "\(renewedCount) prêts prolongés" : "Prêt prolongé"
                feedback = .success
            case (0, _):
                message = refusedCount > 1 ? "Ces prêts ne peuvent pas être prolongés" : "Ce prêt ne peut pas être prolongé"
                feedback = .error
            default:
                message = "\(renewedCount) prolongé\(renewedCount > 1 ? "s" : ""), \(refusedCount) non prolongeable\(refusedCount > 1 ? "s" : "")"
                feedback = .success
            }
            await load()
            // Due dates have changed: reschedule the reminders.
            _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        } catch {
            message = LoadError(error) == .offline ? "Prolongation impossible hors ligne" : "La prolongation n'a pas abouti"
            feedback = .error
        }
    }

    public func dismissMessage() {
        message = nil
    }
}

@MainActor
@Observable
public final class HoldsViewModel {
    public private(set) var state: LoadState<[Hold]> = .idle
    public private(set) var cancelling: Set<Hold.ID> = []
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.accountClient) private var account

    public init() {}

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await account.holds())
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public var ready: [Hold] { (state.value ?? []).filter(\.isReadyForPickup) }
    public var waiting: [Hold] { (state.value ?? []).filter { !$0.isReadyForPickup } }

    public func cancel(_ hold: Hold) async {
        cancelling.insert(hold.id)
        defer { cancelling.remove(hold.id) }
        do {
            try await account.cancelHold(hold.id)
            if case let .loaded(holds) = state { state = .loaded(holds.filter { $0.id != hold.id }) }
            message = "Réservation annulée"
            feedback = .lightImpact
        } catch {
            message = "L'annulation n'a pas abouti"
            feedback = .error
        }
    }
}
