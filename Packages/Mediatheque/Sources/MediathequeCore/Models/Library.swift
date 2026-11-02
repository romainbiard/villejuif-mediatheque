// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// The network's 3 libraries. `code` serves both as `code_annexe`
/// (pickup location) and as the `Y{code}` search facet.
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

    /// Slug of the library's page (`/elsa_triolet`).
    public var slug: String {
        switch self {
        case .elsaTriolet: "elsa_triolet"
        case .pulpSud: "pulp_sud"
        case .pulpNord: "pulp_nord"
        }
    }

    /// Embedded coordinates: the site doesn't publish them. Geocoded from each library's address
    /// (Base Adresse Nationale and Apple agree within 30 m): 1 esplanade Pierre-Yves-Cosnier,
    /// 61 rue Pasteur, 118 rue Youri-Gagarine.
    public var coordinate: (latitude: Double, longitude: Double) {
        switch self {
        case .elsaTriolet: (48.7922, 2.3630)
        case .pulpNord: (48.8049, 2.3663)
        case .pulpSud: (48.7822, 2.3570)
        }
    }

    /// Finds a library from a label on the site
    /// ("Médiathèque Elsa-Triolet", "Pulp Nord", "PULP Sud"…).
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
