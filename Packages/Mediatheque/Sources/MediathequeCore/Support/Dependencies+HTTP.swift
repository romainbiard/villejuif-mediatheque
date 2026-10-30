import BokehAPI
import Dependencies

extension HTTPClient: DependencyKey {
    /// Un seul transport partagé : il porte le cookie de session.
    public static let liveValue = HTTPClient()
}

extension DependencyValues {
    public var httpClient: HTTPClient {
        get { self[HTTPClient.self] }
        set { self[HTTPClient.self] = newValue }
    }
}
