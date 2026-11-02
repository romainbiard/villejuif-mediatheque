// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Account home: the record (counters, card) refreshes on every appearance.
@MainActor
@Observable
final class AccountHomeViewModel {
    private(set) var isRefreshing = false
    /// The refresh failed: the account on screen is the last one read ("Mise à jour impossible" banner).
    private(set) var error: LoadError?
    /// Bell badge.
    private(set) var unreadNotifications = 0

    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.inboxClient) private var inbox

    init() {}

    func refresh(_ session: SessionStore) async {
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshUnreadCount()
        }
        // Snapshot for the widget and offline use, reminders rescheduled, notification center updated.
        // Started alongside the record: each is a few requests to the portal.
        async let sync = try? withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        do {
            let patron = try await account.patron()
            session.update(patron)
            error = nil
            withDependencies(from: self) { AccountSync.record(libraryMessage: patron.message, unread: patron.hasUnreadMessage) }
            _ = await sync
        } catch {
            _ = await sync
            let loadError = LoadError(error)
            if loadError == .notLoggedIn { await session.logout() }
            self.error = loadError
        }
    }

    func refreshUnreadCount() {
        unreadNotifications = inbox.load().unreadCount
    }
}

@MainActor
@Observable
final class LoansViewModel {
    struct Section: Identifiable, Equatable {
        enum Kind: String { case late, thisWeek, later }
        let kind: Kind
        let loans: [Loan]
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .late: .local("En retard")
            case .thisWeek: .local("Cette semaine")
            case .later: .local("Plus tard")
            }
        }
    }

    private(set) var state: LoadState<[Loan]> = .idle
    /// The refresh failed: the loans on screen are the last ones read.
    private(set) var staleError: LoadError?
    private(set) var renewing: Set<Loan.ID> = []
    /// Loans the site refused to renew during this screen session.
    private(set) var refused: Set<Loan.ID> = []
    private(set) var message: String?
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.snapshotClient) private var snapshots
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored private let calendar = Calendar.paris

    init() {}

    /// The last snapshot shows at once, then the portal's list replaces it.
    func load() async {
        if state.value == nil {
            state = snapshots.load().map { .loaded($0.upcomingLoans) } ?? .loading
        }
        do {
            state = try await .loaded(account.loans().sorted { $0.dueDate < $1.dueDate })
            staleError = nil
        } catch {
            if state.value == nil {
                state = .failed(LoadError(error))
            } else {
                staleError = LoadError(error)
            }
        }
    }

    var sections: [Section] {
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

    func dueState(of loan: Loan) -> Loan.DueState {
        loan.dueState(now: now, calendar: calendar)
    }

    func renew(_ loan: Loan) async {
        await renew([loan.id])
    }

    func renewAll() async {
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
                message = String.local("\(renewedCount) prêts prolongés")
                feedback = .success
            case (0, _):
                message = refusedCount > 1 ? String.local("Ces prêts ne peuvent pas être prolongés") : String.local("Ce prêt ne peut pas être prolongé")
                feedback = .error
            default:
                message = String.local("\(renewedCount) prolongés, \(refusedCount) non prolongeables")
                feedback = .success
            }
            await load()
            // Due dates have changed: reschedule the reminders.
            _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        } catch {
            message = LoadError(error) == .offline ? String.local("Prolongation impossible hors ligne") : String.local("La prolongation n'a pas abouti")
            feedback = .error
        }
    }

    func dismissMessage() {
        message = nil
    }
}

@MainActor
@Observable
final class HoldsViewModel {
    private(set) var state: LoadState<[Hold]> = .idle
    /// The refresh failed: the holds on screen are the last ones read.
    private(set) var staleError: LoadError?
    private(set) var cancelling: Set<Hold.ID> = []
    private(set) var message: String?
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.accountClient) private var account
    @ObservationIgnored @Dependency(\.snapshotClient) private var snapshots

    init() {}

    /// The last snapshot shows at once, then the portal's list replaces it.
    func load() async {
        if state.value == nil {
            state = snapshots.load().map { .loaded($0.holds) } ?? .loading
        }
        do {
            state = try await .loaded(account.holds())
            staleError = nil
        } catch {
            if state.value == nil {
                state = .failed(LoadError(error))
            } else {
                staleError = LoadError(error)
            }
        }
    }

    var ready: [Hold] { (state.value ?? []).filter(\.isReadyForPickup) }
    var waiting: [Hold] { (state.value ?? []).filter { !$0.isReadyForPickup } }

    func cancel(_ hold: Hold) async {
        cancelling.insert(hold.id)
        defer { cancelling.remove(hold.id) }
        do {
            try await account.cancelHold(hold.id)
            if case let .loaded(holds) = state { state = .loaded(holds.filter { $0.id != hold.id }) }
            message = String.local("Réservation annulée")
            feedback = .lightImpact
        } catch {
            message = String.local("L'annulation n'a pas abouti")
            feedback = .error
        }
    }
}
