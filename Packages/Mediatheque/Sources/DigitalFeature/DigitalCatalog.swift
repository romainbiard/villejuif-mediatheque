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
    /// Verbe du bouton quand le service s'ouvre sur le web (« Emprunter » pour les livres).
    public var webActionLabel = "Ouvrir"

    public static func == (lhs: DigitalOffer, rhs: DigitalOffer) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct ProviderApp: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        /// Le service se consulte dans l'app : on propose de l'installer avant d'ouvrir.
        case required
        /// Le service s'ouvre sur le web ; l'app est un complément (app musicale, BD…).
        case companion
        /// Lecteur des fichiers empruntés sur le web (Louise Reader pour BiblioAccess).
        case reader
    }

    public struct Highlight: Hashable, Sendable {
        public let systemImage: String
        public let text: String
    }

    public let name: String
    public let publisher: String
    /// Identifiant App Store, pour la fiche d'installation dans l'app.
    public let appStoreID: String
    /// Scheme de l'app, déclaré dans `LSApplicationQueriesSchemes` : sans lui, iOS ne dit pas si elle est installée.
    public let urlScheme: String?
    public let role: Role
    /// Trois arguments au plus pour la feuille « Installer l'app ».
    public let highlights: [Highlight]

    public init(
        name: String, publisher: String, appStoreID: String, urlScheme: String?,
        role: Role, highlights: [Highlight] = []
    ) {
        self.name = name
        self.publisher = publisher
        self.appStoreID = appStoreID
        self.urlScheme = urlScheme
        self.role = role
        self.highlights = highlights
    }

    /// Lien qui ouvre l'app telle quelle (sans connexion), quand elle a un scheme.
    public var launchURL: URL? { urlScheme.flatMap { URL(string: "\($0)://") } }
}

extension ProviderApp.Highlight {
    init(_ systemImage: String, _ text: String) {
        self.init(systemImage: systemImage, text: text)
    }
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
            app: ProviderApp(
                name: "Médiathèque Numérique", publisher: "ARTE France Développement", appStoreID: "1562009751",
                urlScheme: "arte-mednum", role: .required,
                highlights: [
                    .init("play.rectangle", "Cinéma, séries et documentaires"),
                    .init("ticket", "6 crédits par mois, sans publicité"),
                    .init("lock", "Connecté avec votre carte, sans mot de passe"),
                ]
            ),
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
            app: ProviderApp(
                name: "Cafeyn", publisher: "LeKiosque.fr", appStoreID: "626703984",
                urlScheme: "cafeyn", role: .required,
                highlights: [
                    .init("newspaper", "Journaux et magazines, numéros archivés compris"),
                    .init("infinity", "Lecture illimitée"),
                    .init("lock", "Connecté avec votre carte, sans mot de passe"),
                ]
            ),
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
            app: ProviderApp(
                name: "Mozaik par Toutapprendre", publisher: "Learnorama", appStoreID: "1439773174",
                urlScheme: "com.toutapprendre.toutapprendre", role: .required,
                highlights: [
                    .init("graduationcap", "Langues, code de la route, soutien scolaire…"),
                    .init("infinity", "Cours illimités, à votre rythme"),
                    .init("lock", "Connecté avec votre carte, sans mot de passe"),
                ]
            ),
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
            app: ProviderApp(
                name: "Louise Reader", publisher: "Tite Live", appStoreID: "6476110007",
                urlScheme: "baobabapp", role: .reader
            ),
            firstUseSteps: [
                "Empruntez un livre sur BiblioAccess (bouton « Ouvrir »).",
                "Choisissez le téléchargement « LCP » et ouvrez-le dans Louise Reader.",
                "Au premier livre, Louise demande la phrase de déverrouillage ci-dessous.",
            ],
            tutorialURL: tutorial("biblioaccess"), copyableHint: ("Phrase de déverrouillage LCP", "300005"),
            systemImage: "book", colorSeed: 3, webActionLabel: "Emprunter"
        ),
        DigitalOffer(
            id: "bd", category: "BD et mangas", provider: "Izneo",
            summary: "Franco-belge, comics, mangas et webtoons. Une BD commencée reste lisible un an.",
            quota: "10 BD par mois", module: .izneo,
            // L'accès bibliothèque dans l'app IZNEO n'est pas confirmé : le web reste l'entrée principale.
            app: ProviderApp(
                name: "IZNEO", publisher: "izneo", appStoreID: "377397393",
                urlScheme: "izneo", role: .companion
            ),
            firstUseSteps: ["Touchez « Ouvrir » : Izneo s'ouvre ici, déjà connecté."],
            tutorialURL: tutorial("izneo"), copyableHint: nil,
            systemImage: "square.grid.2x2", colorSeed: 1
        ),
        DigitalOffer(
            id: "eureka", category: "Eurêka et musicMe", provider: "Département du Val-de-Marne",
            summary: "Cinéma, cours, livres DYS et la musique en streaming avec musicMe.",
            quota: "2 films par mois, musique illimitée", module: .eureka,
            // musicMe ne déclare pas de scheme : impossible de savoir si l'app est installée.
            app: ProviderApp(
                name: "musicMe pour bibliothèques", publisher: "Apache Network", appStoreID: "1053487668",
                urlScheme: nil, role: .companion
            ),
            firstUseSteps: [
                "Touchez « Ouvrir » : Eurêka s'ouvre déjà connecté.",
                "Pour l'app musicMe : sur le site musicMe, menu « Appli mobile », puis suivez l'e-mail d'activation.",
            ],
            tutorialURL: tutorial("musicme"), copyableHint: nil,
            systemImage: "music.note", colorSeed: 4
        ),
    ]
}
