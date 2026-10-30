import Dependencies
import DependenciesMacros
import Foundation
import LocalAuthentication

/// Face ID / Touch ID, pour verrouiller l'accès au compte à l'ouverture de l'app.
@DependencyClient
public struct BiometricClient: Sendable {
    /// Nom du capteur disponible (« Face ID », « Touch ID »), `nil` s'il n'y en a pas.
    public var availableKind: @Sendable () -> String? = { nil }
    public var authenticate: @Sendable (_ reason: String) async -> Bool = { _ in false }
}

extension BiometricClient: DependencyKey {
    public static let liveValue = BiometricClient(
        availableKind: {
            let context = LAContext()
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
            switch context.biometryType {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            default: return nil
            }
        },
        authenticate: { reason in
            // Le code de l'appareil reste possible si la biométrie échoue.
            (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        }
    )

    public static let previewValue = BiometricClient(availableKind: { "Face ID" }, authenticate: { _ in true })
    public static let testValue = BiometricClient()
}

extension DependencyValues {
    public var biometricClient: BiometricClient {
        get { self[BiometricClient.self] }
        set { self[BiometricClient.self] = newValue }
    }
}
