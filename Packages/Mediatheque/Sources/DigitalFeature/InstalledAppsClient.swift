import Dependencies
import DependenciesMacros
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Savoir si l'app d'un partenaire est installée, par son scheme.
/// iOS ne répond que pour les schemes listés dans `LSApplicationQueriesSchemes` (project.yml).
@DependencyClient
public struct InstalledAppsClient: Sendable {
    public var isInstalled: @MainActor @Sendable (_ urlScheme: String) -> Bool = { _ in false }
    /// Ouvre l'app ; `false` seulement si iOS a refusé (le repli web prend alors le relais).
    public var open: @MainActor @Sendable (_ url: URL) async -> Bool = { _ in false }
}

extension InstalledAppsClient: DependencyKey {
    public static let liveValue = InstalledAppsClient(
        isInstalled: { scheme in
            #if canImport(UIKit)
            guard let url = URL(string: "\(scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
            #else
            return false
            #endif
        },
        open: { url in
            #if canImport(UIKit)
            // `UIApplication.open` directement : l'`openURL` de SwiftUI hors de toute vue répond
            // « échec » au retour dans l'app, et déclenchait à tort le repli web.
            let opened = await UIApplication.shared.open(url)
            // Partie en arrière-plan pendant l'essai : l'app s'est bien ouverte.
            return opened || UIApplication.shared.applicationState != .active
            #else
            return false
            #endif
        }
    )

    public static let previewValue = InstalledAppsClient(isInstalled: { $0 == "cafeyn" }, open: { _ in true })
    public static let testValue = InstalledAppsClient()
}

extension DependencyValues {
    public var installedApps: InstalledAppsClient {
        get { self[InstalledAppsClient.self] }
        set { self[InstalledAppsClient.self] = newValue }
    }
}
