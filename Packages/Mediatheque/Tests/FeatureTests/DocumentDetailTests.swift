// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import SearchFeature

@MainActor
struct DocumentSelectionsTests {
    private let document = SampleData.documents[0]

    @Test func theHeartFollowsTheSiteAndTogglesFavorites() async {
        let sent = LockIsolated<[(DefaultSelection, Bool)]>([])
        let viewModel = withDependencies {
            $0.profileClient.defaultSelections = { _ in [.read] }
            $0.profileClient.setInDefaultSelection = { selection, _, isIn in sent.withValue { $0.append((selection, isIn)) } }
        } operation: { DocumentDetailViewModel(document: document) }

        await viewModel.loadSelections()
        #expect(!viewModel.isIn(.favorites))
        #expect(viewModel.isIn(.read))

        await viewModel.toggle(.favorites)
        #expect(viewModel.isIn(.favorites))
        #expect(viewModel.message == "Ajouté à « Mes préférés »")
        #expect(viewModel.feedback == .lightImpact)
        #expect(sent.value.map(\.0) == [.favorites])
        #expect(sent.value.map(\.1) == [true])

        await viewModel.toggle(.read)
        #expect(!viewModel.isIn(.read))
        #expect(viewModel.message == "Retiré de « Déjà lu »")
    }

    @Test func aRefusedChangeBringsTheHeartBack() async {
        let viewModel = withDependencies {
            $0.profileClient.defaultSelections = { _ in [] }
            $0.profileClient.setInDefaultSelection = { _, _, _ in throw ProfileError.selectionNotChanged }
        } operation: { DocumentDetailViewModel(document: document) }

        await viewModel.loadSelections()
        await viewModel.toggle(.favorites)
        #expect(!viewModel.isIn(.favorites))
        #expect(viewModel.message == "La sélection n'a pas pu être modifiée")
        #expect(viewModel.feedback == .error)
    }

    @Test func nothingToggledBeforeTheSelectionsAreKnown() async {
        // Signed out, or the page didn't load: no request is sent.
        let viewModel = withDependencies {
            $0.profileClient.defaultSelections = { _ in throw URLError(.notConnectedToInternet) }
        } operation: { DocumentDetailViewModel(document: document) }

        await viewModel.loadSelections()
        #expect(viewModel.selections == nil)
        await viewModel.toggle(.favorites)
        #expect(viewModel.message == nil)
    }
}
