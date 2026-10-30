import Foundation

/// Erreurs remontées par le portail Bokeh ou par le transport.
public enum BokehError: Error, Equatable, Sendable {
    /// La session web a expiré ou n'a jamais été ouverte
    /// (`Autorisation non spécifiée` / `Jeton d'autorisation invalide`).
    case unauthorized
    /// Erreur métier renvoyée par l'API JSON (`{"error", "message"}`).
    case api(code: String, message: String)
    /// Réponse HTTP inattendue (5xx, 404…).
    case http(status: Int)
    /// Le contenu reçu ne correspond plus au format attendu.
    case unexpectedFormat(String)
}

/// Corps d'erreur JSON de Bokeh.
struct BokehErrorBody: Decodable {
    let error: String
    let message: String?
}

extension BokehError {
    static let unauthorizedMessages: Set<String> = [
        "Autorisation non spécifiée",
        "Jeton d'autorisation invalide",
    ]

    /// Détecte une erreur Bokeh dans un corps JSON, `nil` si le corps n'en est pas une.
    static func from(json data: Data) -> BokehError? {
        guard let body = try? JSONDecoder().decode(BokehErrorBody.self, from: data) else { return nil }
        let message = body.message ?? body.error
        if unauthorizedMessages.contains(message) { return .unauthorized }
        return .api(code: body.error, message: message)
    }
}
