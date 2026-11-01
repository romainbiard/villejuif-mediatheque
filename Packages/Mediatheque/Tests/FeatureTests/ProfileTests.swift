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

@MainActor
struct SelectionsTests {
    @Test func creatingASelectionReloadsTheList() async {
        let created = LockIsolated<[String]>([])
        let viewModel = withDependencies {
            $0.profileClient.selections = { SampleData.selections + created.value.map { Selection(id: 99, basketID: nil, name: $0, count: 0, updatedAt: nil, coverURLs: []) } }
            $0.profileClient.createSelection = { name in created.withValue { $0.append(name) } }
        } operation: { SelectionsViewModel() }

        await viewModel.load()
        await viewModel.create(named: "  Vacances ")
        #expect(created.value == ["Vacances"])
        #expect(viewModel.state.value?.last?.name == "Vacances")
        #expect(viewModel.feedback == .success)
    }

    @Test func duplicateNameIsRefusedLocally() async {
        let viewModel = withDependencies {
            $0.profileClient.selections = { SampleData.selections }
        } operation: { SelectionsViewModel() }

        await viewModel.load()
        await viewModel.create(named: "à lire")
        #expect(viewModel.message == "Une sélection porte déjà ce nom")
        #expect(viewModel.feedback == .error)
    }

    @Test func removingANoticeUpdatesTheList() async {
        let selection = SampleData.selections[0]
        let viewModel = withDependencies {
            $0.profileClient.selectionNotices = { _, page in
                SearchPage(total: SampleData.documents.count, page: page, pageSize: 10, documents: SampleData.documents)
            }
            $0.profileClient.removeFromSelection = { _, _ in }
        } operation: { SelectionDetailViewModel(selection: selection) }

        await viewModel.load()
        let first = SampleData.documents[0]
        await viewModel.remove(first)
        #expect(viewModel.state.value?.contains { $0.id == first.id } == false)
        #expect(viewModel.message == "Retiré de « Mes préférés »")
    }
}

@MainActor
struct ReviewsAndSuggestionsTests {
    @Test func submittedReviewLeavesTheToRateList() async {
        let viewModel = withDependencies {
            $0.profileClient.recordsToRate = { SampleData.recordsToRate }
            $0.profileClient.reviews = { [] }
            $0.profileClient.submitReview = { _, rating, _, _ in #expect(rating == 5) }
        } operation: { ReviewsViewModel() }

        await viewModel.load()
        let closes = await viewModel.submit(SampleData.recordsToRate[0], rating: 5, title: " Superbe ", text: "")
        #expect(closes)
        #expect(viewModel.toRate.value?.map(\.recordID) == [909376])
        #expect(viewModel.feedback == .success)
    }

    @Test func siteRejectionIsShown() async {
        let viewModel = withDependencies {
            $0.profileClient.sendSuggestion = { _ in throw ProfileError.rejected("Le titre est obligatoire") }
        } operation: { SuggestionsViewModel() }

        viewModel.draft.title = "Dune"
        viewModel.draft.author = "Frank Herbert"
        await viewModel.send()
        #expect(viewModel.message == "Le titre est obligatoire")
        #expect(viewModel.draft.title == "Dune")
        #expect(viewModel.feedback == .error)
    }

    @Test func sentSuggestionResetsTheForm() async {
        let sent = LockIsolated<SuggestionDraft?>(nil)
        let viewModel = withDependencies {
            $0.profileClient.sendSuggestion = { sent.setValue($0) }
            $0.profileClient.suggestions = { [Suggestion(id: "1", title: "Dune", detail: nil)] }
        } operation: { SuggestionsViewModel() }

        viewModel.draft.title = "Dune"
        viewModel.draft.author = "Frank Herbert"
        await viewModel.send()
        #expect(sent.value?.title == "Dune")
        #expect(viewModel.draft == SuggestionDraft())
        #expect(viewModel.sent.value?.count == 1)
    }

    @Test func comicIsSentAsABookWithAComment() {
        #expect(SuggestionKind.comic.docTypeCode == "1")
        #expect(SuggestionKind.dvd.docTypeCode == "4")
    }
}

@MainActor
struct InformationAndSettingsTests {
    @Test func passwordValidation() {
        #expect(InformationViewModel.passwordProblem("", confirmation: "") == "Saisissez un nouveau mot de passe")
        #expect(InformationViewModel.passwordProblem("abc", confirmation: "abd") == "Les deux mots de passe ne correspondent pas")
        #expect(InformationViewModel.passwordProblem("abc", confirmation: "abc") == nil)
    }

    @Test func changedPasswordUpdatesTheKeychain() async {
        let saved = LockIsolated<Credentials?>(nil)
        let viewModel = withDependencies {
            $0.profileClient.changePassword = { _ in }
            $0.keychainClient.load = { Credentials(cardNumber: "0012345", password: "ancien") }
            $0.keychainClient.save = { saved.setValue($0) }
        } operation: { InformationViewModel() }

        let closes = await viewModel.changePassword("nouveau", confirmation: "nouveau")
        #expect(closes)
        #expect(saved.value == Credentials(cardNumber: "0012345", password: "nouveau"))
    }

    @Test func invalidEmailIsNotSent() async {
        let viewModel = withDependencies { _ in } operation: { InformationViewModel() }
        let closes = await viewModel.save(ContactDetails(nickname: "", email: "pas-un-mail", phone: "", channel: .any))
        #expect(!closes)
        #expect(viewModel.message == "Adresse e-mail invalide")
    }

    @Test func bookmarkToggle() async {
        let calls = LockIsolated<[(Library, Bool)]>([])
        let viewModel = withDependencies {
            $0.profileClient.bookmarkedLibraries = { [.pulpNord] }
            $0.profileClient.setLibraryBookmarked = { library, isOn in calls.withValue { $0.append((library, isOn)) } }
        } operation: { ProfileSettingsViewModel(newsletterSubscribed: false) }

        await viewModel.load()
        await viewModel.setBookmarked(.elsaTriolet, true)
        await viewModel.setBookmarked(.pulpNord, true)
        #expect(calls.value.count == 1)
        #expect(viewModel.bookmarks.value == [.pulpNord, .elsaTriolet])
    }
}
