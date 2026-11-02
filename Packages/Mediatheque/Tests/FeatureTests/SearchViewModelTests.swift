// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Clocks
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import SearchFeature

@MainActor
struct SearchViewModelTests {
    @Test func typingIsDebounced() async {
        let clock = TestClock()
        let queries = LockIsolated<[SearchQuery]>([])
        let viewModel = withDependencies {
            $0.continuousClock = clock
            $0.recentSearches.load = { [] }
            $0.catalogClient.search = { query in
                queries.withValue { $0.append(query) }
                return SearchPage(total: 1, page: 1, pageSize: 10, documents: [SampleData.documents[0]])
            }
        } operation: {
            SearchViewModel()
        }

        viewModel.text = "harry"
        viewModel.textDidChange()
        await clock.advance(by: .milliseconds(200))
        viewModel.text = "harry potter"
        viewModel.textDidChange()
        await clock.advance(by: .milliseconds(349))
        #expect(queries.value.isEmpty)

        await clock.advance(by: .milliseconds(1))
        await Task.megaYield()
        #expect(queries.value.map(\.text) == ["harry potter"])
        #expect(viewModel.state.value?.count == 1)
    }

    @Test func scopeSearchesImmediatelyWithItsFacet() async {
        let queries = LockIsolated<[SearchQuery]>([])
        let viewModel = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.recentSearches.load = { [] }
            $0.catalogClient.search = { query in
                queries.withValue { $0.append(query) }
                return SearchPage(total: 0, page: 1, pageSize: 10, documents: [])
            }
        } operation: {
            SearchViewModel()
        }
        viewModel.text = "dune"
        viewModel.select(scope: .dvd)
        await Task.megaYield()

        #expect(queries.value.last?.kinds == [.dvd])
        #expect(viewModel.feedback == .selection)
        #expect(viewModel.state.value?.isEmpty == true)
        #expect(viewModel.hasActiveFilters)
    }

    @Test func submitRemembersRecentSearch() async {
        let saved = LockIsolated<[String]>([])
        let viewModel = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.recentSearches.load = { ["astérix"] }
            $0.recentSearches.save = { saved.setValue($0) }
            $0.catalogClient.search = { _ in SearchPage(total: 0, page: 1, pageSize: 10, documents: []) }
        } operation: {
            SearchViewModel()
        }
        viewModel.text = "Harry Potter "
        viewModel.submit()
        #expect(saved.value == ["Harry Potter", "astérix"])
    }

    @Test func exploreShortcutBrowsesNewestWithoutText() async {
        let queries = LockIsolated<[SearchQuery]>([])
        let viewModel = withDependencies {
            $0.recentSearches.load = { [] }
            $0.catalogClient.search = { query in
                queries.withValue { $0.append(query) }
                return SearchPage(total: 0, page: 1, pageSize: 10, documents: [])
            }
        } operation: {
            SearchViewModel()
        }
        viewModel.open(ExploreShortcut.all[0])
        await Task.megaYield()
        #expect(viewModel.showsLanding == false)
        #expect(queries.value.first?.sort == .newest)
        #expect(queries.value.first?.text == "")
    }

    @Test func nextPageIsAppendedWithoutDuplicates() async {
        let documents = SampleData.documents
        let viewModel = withDependencies {
            $0.recentSearches.load = { [] }
            $0.catalogClient.search = { query in
                query.page == 1
                    ? SearchPage(total: 3, page: 1, pageSize: 2, documents: Array(documents.prefix(2)))
                    : SearchPage(total: 3, page: 2, pageSize: 2, documents: Array(documents.suffix(2)))
            }
        } operation: {
            SearchViewModel()
        }
        viewModel.text = "x"
        await viewModel.runSearch()
        await viewModel.loadNextPage()
        #expect(viewModel.state.value?.map(\.id) == documents.map(\.id))
    }

    @Test func failureIsReported() async {
        let viewModel = withDependencies {
            $0.recentSearches.load = { [] }
            $0.catalogClient.search = { _ in throw URLError(.notConnectedToInternet) }
        } operation: {
            SearchViewModel()
        }
        viewModel.text = "x"
        await viewModel.runSearch()
        #expect(viewModel.state == .failed(.offline))
    }
}
