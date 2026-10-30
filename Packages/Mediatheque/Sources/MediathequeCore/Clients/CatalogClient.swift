import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Catalogue public : recherche JSON et disponibilité en temps réel.
@DependencyClient
public struct CatalogClient: Sendable {
    public var search: @Sendable (_ query: SearchQuery) async throws -> SearchPage
    /// Badge temps réel d'une notice (le statut du JSON de recherche date de la nuit).
    public var availability: @Sendable (_ recordID: Int) async throws -> Availability
    /// Exemplaires temps réel : médiathèque, cote, date de retour, réservations.
    public var copies: @Sendable (_ recordID: Int) async throws -> [LiveCopy]
}

extension CatalogClient: DependencyKey {
    public static var liveValue: CatalogClient {
        @Dependency(\.httpClient) var http
        return CatalogClient(
            search: { query in
                let endpoint = Endpoint.search(query.text, facets: query.facets, sort: query.sort.rawValue, page: query.page)
                return SearchPage(dto: try await http.decode(SearchResponseDTO.self, from: endpoint))
            },
            availability: { recordID in
                let badge = try HTMLParsers.availability(in: try await http.string(for: .availability(recordID: recordID)))
                return Availability(label: badge.label, isAvailable: badge.isAvailable)
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
