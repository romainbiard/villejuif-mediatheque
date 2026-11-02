// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation

/// Recent searches, stored on the device.
@DependencyClient
public struct RecentSearchesClient: Sendable {
    public var load: @Sendable () -> [String] = { [] }
    public var save: @Sendable (_ searches: [String]) -> Void
}

extension RecentSearchesClient: DependencyKey {
    static let key = "recentSearches"

    public static let liveValue = RecentSearchesClient(
        load: { UserDefaults.standard.stringArray(forKey: key) ?? [] },
        save: { UserDefaults.standard.set($0, forKey: key) }
    )

    public static let previewValue = RecentSearchesClient(
        load: { ["harry potter", "astérix et le griffon"] },
        save: { _ in }
    )

    public static let testValue = RecentSearchesClient()
}

extension DependencyValues {
    public var recentSearches: RecentSearchesClient {
        get { self[RecentSearchesClient.self] }
        set { self[RecentSearchesClient.self] = newValue }
    }
}
