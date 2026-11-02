// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies

extension HTTPClient: DependencyKey {
    /// A single shared transport: it carries the session cookie.
    public static let liveValue = HTTPClient()
}

extension DependencyValues {
    public var httpClient: HTTPClient {
        get { self[HTTPClient.self] }
        set { self[HTTPClient.self] = newValue }
    }
}
