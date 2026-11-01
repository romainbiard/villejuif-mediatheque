// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Tells whether a partner's app is installed, by its scheme.
/// iOS only answers for schemes listed in `LSApplicationQueriesSchemes` (project.yml).
@DependencyClient
public struct InstalledAppsClient: Sendable {
    public var isInstalled: @MainActor @Sendable (_ urlScheme: String) -> Bool = { _ in false }
    /// Opens the app; `false` only if iOS refused (the web fallback then takes over).
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
            // `UIApplication.open` directly: SwiftUI's `openURL` outside any view reports
            // "failure" on returning to the app, and wrongly triggered the web fallback.
            let opened = await UIApplication.shared.open(url)
            // Went to the background during the attempt: the app did open.
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
