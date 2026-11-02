// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Public catalog: JSON search and real-time availability.
@DependencyClient
public struct CatalogClient: Sendable {
    public var search: @Sendable (_ query: SearchQuery) async throws -> SearchPage
    /// Real-time badge for a record (the status in the search JSON dates from the night before).
    public var availability: @Sendable (_ recordID: Int) async throws -> Availability
    /// Real-time copies: library, call number, due date, holds.
    public var copies: @Sendable (_ recordID: Int) async throws -> [LiveCopy]
}

extension CatalogClient: DependencyKey {
    public static var liveValue: CatalogClient {
        @Dependency(\.httpClient) var http
        return CatalogClient(
            search: { query in
                let endpoint = Endpoint.search(query.text, facets: query.facets, sort: query.sort.rawValue, page: query.page)
                // Kept in memory for 5 min: switching filters and back, or reopening a recent search, is instant.
                return try await DataCache.shared.value(for: "search-\(endpoint.cacheKey)", maxAge: 5 * 60, persist: false) {
                    SearchPage(dto: try await http.decode(SearchResponseDTO.self, from: endpoint))
                }
            },
            availability: { recordID in
                // The badge must stay close to real time: 2 min, just enough to avoid re-fetching it while scrolling.
                try await DataCache.shared.value(for: "availability-\(recordID)", maxAge: 2 * 60, persist: false) {
                    let badge = try HTMLParsers.availability(in: try await http.string(for: .availability(recordID: recordID)))
                    return Availability(label: badge.label, isAvailable: badge.isAvailable)
                }
            },
            copies: { recordID in
                try HTMLParsers.copies(in: try await http.string(for: .copies(recordID: recordID))).map(LiveCopy.init(dto:))
            }
        )
    }

    public static let previewValue = CatalogClient(
        search: { query in
            SearchPage(total: SampleData.documents.count, page: query.page, pageSize: 10, documents: SampleData.documents)
        },
        availability: { recordID in
            recordID.isMultiple(of: 2)
                ? Availability(label: "Disponible", isAvailable: true)
                : Availability(label: "En prêt", isAvailable: false)
        },
        copies: { _ in SampleData.copies }
    )

    public static let testValue = CatalogClient()
}

extension DependencyValues {
    public var catalogClient: CatalogClient {
        get { self[CatalogClient.self] }
        set { self[CatalogClient.self] = newValue }
    }
}
