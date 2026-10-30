import Foundation

/// Les 3 médiathèques du réseau. `code` sert à la fois de `code_annexe`
/// (lieu de retrait) et de facette de recherche `Y{code}`.
public enum Library: String, CaseIterable, Sendable, Codable, Identifiable {
    case elsaTriolet = "1"
    case pulpSud = "2"
    case pulpNord = "3"

    public var id: String { rawValue }
    public var code: String { rawValue }
    public var searchFacet: String { "Y\(rawValue)" }

    public var name: String {
        switch self {
        case .elsaTriolet: "Médiathèque Elsa-Triolet"
        case .pulpSud: "PULP Sud"
        case .pulpNord: "PULP Nord"
        }
    }

    public var shortName: String {
        switch self {
        case .elsaTriolet: "Elsa-Triolet"
        case .pulpSud: "PULP Sud"
        case .pulpNord: "PULP Nord"
        }
    }

    /// Slug de la page de la médiathèque (`/elsa_triolet`).
    public var slug: String {
        switch self {
        case .elsaTriolet: "elsa_triolet"
        case .pulpSud: "pulp_sud"
        case .pulpNord: "pulp_nord"
        }
    }

    /// Coordonnées embarquées : le site ne les publie pas. Elsa-Triolet vient du GEO
    /// d'un iCal du site ; les deux PULP sont approximées d'après l'adresse, à confirmer.
    public var coordinate: (latitude: Double, longitude: Double) {
        switch self {
        case .elsaTriolet: (48.792636, 2.362783)
        case .pulpNord: (48.7987, 2.3633)
        case .pulpSud: (48.7810, 2.3541)
        }
    }

    /// Retrouve une médiathèque à partir d'un libellé du site
    /// (« Médiathèque Elsa-Triolet », « Pulp Nord », « PULP Sud »…).
    public init?(label: String) {
        let normalized = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if normalized.contains("elsa") { self = .elsaTriolet }
        else if normalized.contains("pulp nord") { self = .pulpNord }
        else if normalized.contains("pulp sud") { self = .pulpSud }
        else { return nil }
    }

    public init?(slug: String) {
        guard let library = Library.allCases.first(where: { $0.slug == slug }) else { return nil }
        self = library
    }
}
