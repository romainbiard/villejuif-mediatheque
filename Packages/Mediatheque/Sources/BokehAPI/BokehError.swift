// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Errors reported by the Bokeh portal or by the transport.
public enum BokehError: Error, Equatable, Sendable {
    /// The web session has expired or was never opened
    /// (`Autorisation non spécifiée` / `Jeton d'autorisation invalide`).
    case unauthorized
    /// Business error returned by the JSON API (`{"error", "message"}`).
    case api(code: String, message: String)
    /// Unexpected HTTP response (5xx, 404…).
    case http(status: Int)
    /// The content received no longer matches the expected format.
    case unexpectedFormat(String)
}

/// Bokeh JSON error body.
struct BokehErrorBody: Decodable {
    let error: String
    let message: String?
}

extension BokehError {
    static let unauthorizedMessages: Set<String> = [
        "Autorisation non spécifiée",
        "Jeton d'autorisation invalide"
    ]

    /// Detects a Bokeh error in a JSON body, `nil` if the body isn't one.
    static func from(json data: Data) -> BokehError? {
        guard let body = try? JSONDecoder().decode(BokehErrorBody.self, from: data) else { return nil }
        let message = body.message ?? body.error
        if unauthorizedMessages.contains(message) { return .unauthorized }
        return .api(code: body.error, message: message)
    }
}
