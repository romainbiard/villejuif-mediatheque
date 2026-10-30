import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing

private func paris(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    Calendar.paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

struct ReminderPlannerTests {
    @Test func remindersBeforeAndOnDueDayInTheFutureOnly() {
        let reminders = ReminderPlanner.loanReminders(
            for: SampleData.loans, daysBefore: 3, now: paris(2026, 10, 30, 9), calendar: .paris
        )
        // Le Petit Prince (28/10) est déjà passé ; Sway (5/11) et Chien pourri (19/11) donnent 2 rappels chacun.
        #expect(reminders.count == 4)
        #expect(reminders.first?.fireDate == paris(2026, 11, 2, 10))
        #expect(reminders.first?.body.contains("« Sway »") == true)
        #expect(reminders.allSatisfy { $0.id.hasPrefix("loan-") })
    }

    @Test func loansDueTheSameDayShareOneReminder() {
        let due = paris(2026, 11, 20)
        let loans = (1...3).map {
            Loan(id: "1_\($0)", title: "Livre \($0)", author: "", dueDate: due, library: .pulpNord,
                 libraryName: "PULP Nord", recordID: nil, coverURL: nil)
        }
        let reminders = ReminderPlanner.loanReminders(for: loans, daysBefore: 3, now: paris(2026, 10, 30), calendar: .paris)
        #expect(reminders.count == 2)
        #expect(reminders[0].body.hasPrefix("3 documents"))
    }

    @Test func newlyReadyHoldsComparedToPrevious() {
        let waiting = SampleData.holds[1]
        let ready = SampleData.holds[0]
        let before = AccountSnapshot(loans: [], holds: [waiting], updatedAt: .distantPast)
        let after = AccountSnapshot(loans: [], holds: [ready, waiting], updatedAt: .now)
        #expect(after.newlyReadyHolds(since: before).map(\.id) == [ready.id])
        #expect(after.newlyReadyHolds(since: after).isEmpty)
    }
}

struct AccountSyncTests {
    @Test func syncSavesSnapshotSchedulesRemindersAndNotifiesArrivals() async throws {
        let saved = LockIsolated<AccountSnapshot?>(nil)
        let scheduled = LockIsolated<[Reminder]>([])
        let delivered = LockIsolated<[Reminder]>([])
        let inbox = LockIsolated<Inbox?>(nil)
        let previous = AccountSnapshot(loans: [], holds: [SampleData.holds[1]], updatedAt: .distantPast)

        try await withDependencies {
            $0.date.now = paris(2026, 10, 30, 9)
            $0.accountClient.loans = { SampleData.loans }
            $0.accountClient.holds = { SampleData.holds }
            $0.snapshotClient.load = { previous }
            $0.snapshotClient.save = { saved.setValue($0) }
            $0.notificationClient.replaceLoanReminders = { scheduled.setValue($0) }
            $0.notificationClient.deliver = { reminder in delivered.withValue { $0.append(reminder) } }
            $0.inboxClient.load = { Inbox() }
            $0.inboxClient.save = { inbox.setValue($0) }
        } operation: {
            try await AccountSync.run(settings: ReminderSettings())
        }

        #expect(saved.value?.loans.count == 3)
        #expect(scheduled.value.count == 4)
        #expect(delivered.value.map(\.title) == ["Murmuration vous attend"])
        // Le 30/10 : Le Petit Prince en retard, Sway à rendre le 5/11 (J-6, hors fenêtre), Murmuration arrivé.
        #expect(inbox.value?.items.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.holdReady, .loanLate])
    }

    @Test func firstSyncDoesNotNotifyAndDisabledRemindersAreCleared() async throws {
        let scheduled = LockIsolated<[Reminder]?>(nil)
        try await withDependencies {
            $0.date.now = paris(2026, 10, 30, 9)
            $0.accountClient.loans = { SampleData.loans }
            $0.accountClient.holds = { SampleData.holds }
            $0.snapshotClient.load = { nil }
            $0.snapshotClient.save = { _ in }
            $0.notificationClient.replaceLoanReminders = { scheduled.setValue($0) }
            $0.inboxClient.load = { Inbox() }
            $0.inboxClient.save = { _ in }
        } operation: {
            try await AccountSync.run(settings: ReminderSettings(loanReminders: false))
        }
        #expect(scheduled.value == [])
    }
}

@MainActor
struct FaceIDTests {
    func makeSession(authenticates: Bool, defaults: UserDefaults) -> SessionStore {
        withDependencies {
            $0.keychainClient.load = { Credentials(cardNumber: "0012345", password: "x") }
            $0.biometricClient.authenticate = { _ in authenticates }
            $0.authClient.restore = { SampleData.patron }
        } operation: {
            SessionStore(defaults: defaults)
        }
    }

    @Test func faceIDRefusedKeepsTheAccountLocked() async {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let session = makeSession(authenticates: false, defaults: defaults)
        session.isFaceIDEnabled = true
        await session.restore()
        #expect(session.state == .locked)
        await session.unlock()
        #expect(session.state == .locked)
    }

    @Test func faceIDAcceptedOpensTheAccount() async {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let session = makeSession(authenticates: true, defaults: defaults)
        session.isFaceIDEnabled = true
        await session.restore()
        #expect(session.patron == SampleData.patron)
    }

    @Test func withoutFaceIDTheSessionRestoresDirectly() async {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let session = makeSession(authenticates: false, defaults: defaults)
        await session.restore()
        #expect(session.patron == SampleData.patron)
    }
}
