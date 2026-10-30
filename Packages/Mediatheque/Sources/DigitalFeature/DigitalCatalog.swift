import Foundation
import MediathequeCore

/// Description d'un service numérique, embarquée dans l'app (tirée des tutoriels du site).
public struct DigitalOffer: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: String
    public let provider: String
    public let summary: String
    public let quota: String
    /// Module Bokeh qui ouvre la session chez le fournisseur.
    public let module: DigitalService
    public let app: ProviderApp?
    /// Étapes de première utilisation, trois au plus.
    public let firstUseSteps: [String]
    public let tutorialURL: URL
    /// Information à copier en un tap (phrase de déverrouillage LCP pour BiblioAccess).
    public let copyableHint: (label: String, value: String)?
    public let systemImage: String
    public let colorSeed: Int

    public static func == (lhs: DigitalOffer, rhs: DigitalOffer) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct ProviderApp: Hashable, Sendable {
    public let name: String
    /// Identifiant App Store, pour la fiche d'installation dans l'app.
    public let appStoreID: String
}

public enum DigitalCatalog {
    static func tutorial(_ name: String) -> URL {
        URL(string: "https://mediatheque.villejuif.fr/userfiles/file/mediatheque-numerique_tutoriels/mediatheque-numerique_tuto-\(name).pdf")!
    }

    public static let offers: [DigitalOffer] = [
        DigitalOffer(
            id: "films", category: "Films et séries", provider: "Arte VOD et Univers Ciné",
            summary: "Des milliers de films, documentaires, séries et spectacles, en plusieurs langues.",
            quota: "6 crédits par mois, renouvelés le 1er", module: .arteVod,
            app: ProviderApp(name: "Médiathèque Numérique", appStoreID: "1562009751"),
            firstUseSteps: [
                "Installez l'app Médiathèque Numérique.",
                "Revenez ici et touchez « Ouvrir » : la plateforme vous reconnaît.",
                "L'app reste connectée ensuite, vous n'aurez plus à le refaire.",
            ],
            tutorialURL: tutorial("arte-vod-univers-cine"), copyableHint: nil,
            systemImage: "film", colorSeed: 5
        ),
        DigitalOffer(
            id: "presse", category: "Presse", provider: "Cafeyn",
            summary: "Plus de 2 500 journaux et magazines, avec les numéros archivés.",
            quota: "Illimité", module: .cafeyn,
            app: ProviderApp(name: "Cafeyn", appStoreID: "626703984"),
            firstUseSteps: [
                "Installez l'app Cafeyn.",
                "Revenez ici et touchez « Ouvrir » : Cafeyn s'ouvre déjà connecté.",
            ],
            tutorialURL: tutorial("cafeyn"), copyableHint: nil,
            systemImage: "newspaper", colorSeed: 0
        ),
        DigitalOffer(
            id: "formation", category: "Formation", provider: "Mozaik par Toutapprendre",
            summary: "Langues, code de la route, soutien scolaire, bureautique, sport, musique…",
            quota: "Illimité", module: .toutApprendre,
            app: ProviderApp(name: "Mozaik par Toutapprendre", appStoreID: "1439773174"),
            firstUseSteps: [
                "Installez l'app Mozaik.",
                "Touchez « Ouvrir » ici : si l'app ne s'ouvre pas connectée, allez dans « Mon compte » sur Mozaik.",
                "Le QR code de « Mon compte » se scanne depuis l'app Mozaik d'un autre appareil.",
            ],
            tutorialURL: tutorial("mozaik"), copyableHint: nil,
            systemImage: "graduationcap", colorSeed: 2
        ),
        DigitalOffer(
            id: "ebooks", category: "Livres numériques et audio", provider: "BiblioAccess",
            summary: "Empruntez des e-books et des livres audio, à lire en ligne ou à télécharger.",
            quota: "5 e-books et 5 livres audio, 3 semaines", module: .numilog,
            app: ProviderApp(name: "Louise Reader", appStoreID: "6476110007"),
            firstUseSteps: [
                "Empruntez un livre sur BiblioAccess (bouton « Ouvrir »).",
                "Choisissez le téléchargement « LCP » et ouvrez-le dans Louise Reader.",
                "Au premier livre, Louise demande la phrase de déverrouillage ci-dessous.",
            ],
            tutorialURL: tutorial("biblioaccess"), copyableHint: ("Phrase de déverrouillage LCP", "300005"),
            systemImage: "book", colorSeed: 3
        ),
        DigitalOffer(
            id: "bd", category: "BD et mangas", provider: "Izneo",
            summary: "Franco-belge, comics, mangas et webtoons. Une BD commencée reste lisible un an.",
            quota: "10 BD par mois", module: .izneo, app: nil,
            firstUseSteps: ["Touchez « Ouvrir » : Izneo s'ouvre ici, déjà connecté."],
            tutorialURL: tutorial("izneo"), copyableHint: nil,
            systemImage: "square.grid.2x2", colorSeed: 1
        ),
        DigitalOffer(
            id: "eureka", category: "Eurêka et musicMe", provider: "Département du Val-de-Marne",
            summary: "Cinéma, cours, livres DYS et la musique en streaming avec musicMe.",
            quota: "2 films par mois, musique illimitée", module: .eureka,
            app: ProviderApp(name: "musicMe pour bibliothèques", appStoreID: "1053487668"),
            firstUseSteps: [
                "Touchez « Ouvrir » : Eurêka s'ouvre déjà connecté.",
                "Pour l'app musicMe : sur le site musicMe, menu « Appli mobile », puis suivez l'e-mail d'activation.",
            ],
            tutorialURL: tutorial("musicme"), copyableHint: nil,
            systemImage: "music.note", colorSeed: 4
        ),
    ]
}
