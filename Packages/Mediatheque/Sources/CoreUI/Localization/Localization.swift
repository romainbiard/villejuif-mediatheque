// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

// Text of this module, looked up in its own String Catalog (Localizable.xcstrings, next to this file).
// Inside a Swift package, a plain `Text("…")` would look in the app's bundle instead.

extension String {
    /// For labels passed as `String`.
    static func local(_ key: LocalizationValue, comment: StaticString? = nil) -> String {
        String(localized: key, bundle: .module, comment: comment)
    }
}
