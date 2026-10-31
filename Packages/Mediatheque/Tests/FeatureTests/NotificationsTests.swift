import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import AccountFeature

private func paris(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    Calendar.paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

struct InboxPlannerTests {
    let snapshot = AccountSnapshot(loans: SampleData.loans, holds: SampleData.holds, updatedAt: .distantPast)

    @Test func lateDueSoonAndReadyHoldsBecomeItems() {
        // Le 2/11 : Le Petit Prince en retard depuis le 28/10, Sway à rendre le 5/11 (J-3).
        let items = InboxPlanner.items(for: snapshot, daysBefore: 3, now: paris(2026, 11, 2), calendar: .paris)
        #expect(items.map(\.kind) == [.loanLate, .loanDueSoon, .holdReady])
        #expect(items[0].loanID == "100001_1")
        #expect(items[1].title == "« Sway » est à rendre dans 3 jours")
        #expect(items[1].date <= paris(2026, 11, 2))
    }

    @Test func idsAreStableBetweenSyncs() {
        let first = InboxPlanner.items(for: snapshot, daysBefore: 3, now: paris(2026, 11, 2, 9), calendar: .paris)
        let second = InboxPlanner.items(for: snapshot, daysBefore: 3, now: paris(2026, 11, 2, 18), calendar: .paris)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(InboxPlanner.libraryMessage("Fermé le 11/11", now: .now).id == InboxPlanner.libraryMessage("Fermé le 11/11", now: .now).id)
    }

    @Test func mergeKeepsReadStateAndForgetsOldItems() {
        let now = paris(2026, 11, 2)
        var inbox = Inbox(items: [
            InboxItem(id: "a", kind: .holdReady, title: "A", body: "", date: paris(2026, 11, 1), isRead: true),
            InboxItem(id: "old", kind: .holdReady, title: "Vieux", body: "", date: paris(2026, 9, 1)),
        ])
        let added = inbox.merge([
            InboxItem(id: "a", kind: .holdReady, title: "A", body: "", date: now),
            InboxItem(id: "b", kind: .loanLate, title: "B", body: "", date: now),
        ], now: now, calendar: .paris)

        #expect(added.map(\.id) == ["b"])
        #expect(inbox.items.map(\.id) == ["b", "a"])
        #expect(inbox.items.last?.isRead == true)
        #expect(inbox.unreadCount == 1)
    }

    @Test func messageIsStrippedOfHTML() {
        let item = InboxPlanner.libraryMessage("<p>Fermeture <b>exceptionnelle</b></p>", now: .now)
        #expect(item.body == "Fermeture exceptionnelle")
    }
}

@MainActor
struct NotificationsViewModelTests {
    @Test func itemsAreGroupedByDay() {
        let viewModel = withDependencies {
            $0.date.now = paris(2026, 10, 30, 18)
            $0.inboxClient.load = { SampleData.inbox }
        } operation: { NotificationsViewModel() }

        viewModel.load()
        #expect(viewModel.sections.map(\.kind) == [.today, .thisWeek])
        #expect(viewModel.sections.last?.items.map(\.kind) == [.loanLate, .libraryMessage])
    }

    @Test func markAllReadIsSaved() {
        let saved = LockIsolated<Inbox?>(nil)
        let viewModel = withDependencies {
            $0.inboxClient.load = { SampleData.inbox }
            $0.inboxClient.save = { saved.setValue($0) }
        } operation: { NotificationsViewModel() }

        viewModel.load()
        viewModel.markAllRead()
        #expect(saved.value?.unreadCount == 0)
        #expect(viewModel.feedback == .lightImpact)
    }

    @Test func renewFromTheListMarksTheItemRead() async throws {
        let saved = LockIsolated<Inbox?>(nil)
        let viewModel = withDependencies {
            $0.date.now = paris(2026, 10, 30)
            $0.inboxClient.load = { saved.value ?? SampleData.inbox }
            $0.inboxClient.save = { saved.setValue($0) }
            $0.accountClient.renew = { ids in ids.map { .renewed(loanID: $0, newDueDate: paris(2026, 11, 20)) } }
            $0.accountClient.loans = { SampleData.loans }
            $0.accountClient.holds = { [] }
            $0.snapshotClient.load = { nil }
            $0.snapshotClient.save = { _ in }
            $0.notificationClient.replaceLoanReminders = { _ in }
            $0.notificationClient.setAgendaDigest = { _ in }
        } operation: { NotificationsViewModel() }

        viewModel.load()
        let late = try #require(viewModel.inbox.items.first { $0.kind == .loanLate })
        await viewModel.renew(late)
        #expect(viewModel.message == "Prolongé jusqu'au 20 novembre")
        #expect(!viewModel.canRenew(late))
        #expect(saved.value?.items.first { $0.id == late.id }?.isRead == true)
    }
}
