// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import AccountFeature
@testable import SearchFeature

func freshDefaults() -> UserDefaults {
    let name = "tests.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

private func paris(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    Calendar.paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor
struct SessionAndLoginTests {
    @Test func restoreWithoutCredentialsIsLoggedOut() async {
        let session = withDependencies {
            $0.keychainClient.load = { nil }
            $0.authClient.restore = { nil }
        } operation: { SessionStore(defaults: freshDefaults()) }
        await session.restore()
        #expect(session.state == .loggedOut)
    }

    @Test func successfulLoginOpensSession() async {
        let (session, viewModel) = withDependencies {
            $0.authClient.login = { credentials in
                #expect(credentials == Credentials(cardNumber: "0012345", password: "secret"))
                return SampleData.patron
            }
        } operation: { (SessionStore(defaults: freshDefaults()), LoginViewModel()) }

        viewModel.cardNumber = " 0012345 "
        viewModel.password = "secret"
        await viewModel.submit(into: session)

        #expect(session.patron == SampleData.patron)
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.feedback == .success)
    }

    @Test func invalidCredentialsShowsMessage() async {
        let (session, viewModel) = withDependencies {
            $0.authClient.login = { _ in throw AuthError.invalidCredentials }
        } operation: { (SessionStore(defaults: freshDefaults()), LoginViewModel()) }

        viewModel.cardNumber = "1"
        viewModel.password = "x"
        await viewModel.submit(into: session)

        #expect(session.patron == nil)
        #expect(viewModel.errorMessage == "Numéro de carte ou mot de passe incorrect.")
        #expect(viewModel.feedback == .error)
    }

    @Test func cannotSubmitEmptyForm() {
        let viewModel = LoginViewModel()
        viewModel.cardNumber = "0012345"
        #expect(viewModel.canSubmit == false)
    }
}

@MainActor
struct LoansViewModelTests {
    func makeViewModel(renew: @escaping @Sendable ([Loan.ID]) async throws -> [RenewalResult]) async -> LoansViewModel {
        let viewModel = withDependencies {
            $0.date.now = paris(2026, 10, 30)
            $0.accountClient.loans = { SampleData.loans }
            $0.accountClient.renew = renew
            // Renewal restarts the sync (snapshot, reminders) with these dependencies.
            $0.accountClient.holds = { [] }
            $0.snapshotClient.load = { nil }
            $0.snapshotClient.save = { _ in }
            $0.notificationClient.replaceLoanReminders = { _ in }
            $0.notificationClient.setAgendaDigest = { _ in }
            $0.inboxClient.load = { Inbox() }
            $0.inboxClient.save = { _ in }
        } operation: { LoansViewModel() }
        await viewModel.load()
        return viewModel
    }

    @Test func loansAreGroupedByDueState() async {
        let viewModel = await makeViewModel(renew: { _ in [] })
        #expect(viewModel.sections.map(\.kind) == [.late, .thisWeek, .later])
        #expect(viewModel.sections.first?.loans.first?.title == "Le Petit Prince")
    }

    @Test func renewAllReportsMixedResult() async {
        let viewModel = await makeViewModel(renew: { ids in
            ids.map { $0 == "100001_3" ? .refused(loanID: $0) : .renewed(loanID: $0, newDueDate: paris(2026, 12, 1)) }
        })
        await viewModel.renewAll()
        #expect(viewModel.message == "2 prolongés, 1 non prolongeable")
        #expect(viewModel.refused == ["100001_3"])
        #expect(viewModel.renewing.isEmpty)
        #expect(viewModel.feedback == .success)
    }

    @Test func refusedRenewalIsAnError() async {
        let viewModel = await makeViewModel(renew: { ids in ids.map { .refused(loanID: $0) } })
        await viewModel.renew(SampleData.loans[0])
        #expect(viewModel.message == "Ce prêt ne peut pas être prolongé")
        #expect(viewModel.feedback == .error)
    }
}

@MainActor
struct HoldsTests {
    @Test func holdsAreSplitAndCancelled() async {
        let cancelled = LockIsolated<[Hold.ID]>([])
        let viewModel = withDependencies {
            $0.accountClient.holds = { SampleData.holds }
            $0.accountClient.cancelHold = { id in cancelled.withValue { $0.append(id) } }
        } operation: { HoldsViewModel() }
        await viewModel.load()

        #expect(viewModel.ready.map(\.title) == ["Murmuration"])
        #expect(viewModel.waiting.count == 1)

        await viewModel.cancel(SampleData.holds[1])
        #expect(cancelled.value == ["100001_11"])
        #expect(viewModel.waiting.isEmpty)
        #expect(viewModel.message == "Réservation annulée")
    }

    @Test func placingAHoldUsesTheChosenPickup() async {
        let placed = LockIsolated<Library?>(nil)
        let request = HoldRequest(recordID: 909376, pickupPath: "p", pickupLibraries: Library.allCases, defaultPickup: .pulpNord)
        let viewModel = withDependencies {
            $0.accountClient.prepareHold = { _ in request }
            $0.accountClient.placeHold = { _, pickup in
                placed.setValue(pickup)
                return "Votre réservation est enregistrée.\nNous vous informerons quand le document sera disponible"
            }
        } operation: { HoldViewModel(notice: SampleData.documents[0], defaultPickup: nil) }

        await viewModel.prepare()
        #expect(viewModel.pickup == .pulpNord)
        viewModel.pickup = .elsaTriolet
        await viewModel.submit()

        #expect(placed.value == .elsaTriolet)
        guard case let .confirmed(_, pickup) = viewModel.step else { Issue.record("pas confirmé"); return }
        #expect(pickup == .elsaTriolet)
        #expect(viewModel.feedback == .success)
    }

    @Test func notHoldableIsExplained() async {
        let viewModel = withDependencies {
            $0.accountClient.prepareHold = { _ in throw HoldError.notHoldable }
        } operation: { HoldViewModel(notice: SampleData.documents[0], defaultPickup: .pulpNord) }
        await viewModel.prepare()
        #expect(viewModel.step == .failed("Ce document ne peut pas être réservé pour le moment."))
    }
}
