// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

// The DesignSystem components, built from a `LoadError`: this module links the two,
// so that DesignSystem stays unaware of the domain and MediathequeCore of the interface.

public extension EmptyStateView {
    /// Nothing to show because loading failed: what went wrong, and a retry button.
    init(error: LoadError, retry: @escaping () async -> Void) {
        self.init(
            systemImage: error.systemImage,
            title: error.title,
            message: error.message,
            primary: (String.local("Réessayer"), { Task { await retry() } })
        )
    }
}

public extension StaleBanner {
    /// The refresh failed over data already on screen.
    init(error: LoadError) {
        self.init(error.staleText, systemImage: error.staleSystemImage)
    }
}
