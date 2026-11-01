// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation
import LocalAuthentication

/// Face ID / Touch ID, to lock access to the account when the app opens.
@DependencyClient
public struct BiometricClient: Sendable {
    /// Name of the available sensor ("Face ID", "Touch ID"), `nil` if there is none.
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
            // The device passcode remains an option if biometrics fail.
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
