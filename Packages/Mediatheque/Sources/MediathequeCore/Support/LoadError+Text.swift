// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// What a screen says above the data it already shows when the refresh failed.
/// Text only: the banner comes from `DesignSystem`.
extension LoadError {
    /// Short line above cached data: "Hors ligne", "Mise à jour impossible"…
    public var staleText: String {
        switch self {
        case .offline: .local("Hors ligne · dernières données enregistrées")
        default: .local("Mise à jour impossible · dernières données enregistrées")
        }
    }

    public var staleSystemImage: String {
        switch self {
        case .offline: "wifi.slash"
        default: "icloud.slash"
        }
    }
}
