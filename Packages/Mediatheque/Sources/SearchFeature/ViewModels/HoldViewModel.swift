// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Hold on a record: preparation (pickup locations), choice, submission.
@MainActor
@Observable
public final class HoldViewModel {
    public enum Step: Equatable {
        case preparing
        case choosing(HoldRequest)
        case submitting(HoldRequest)
        case confirmed(message: String, pickup: Library)
        case failed(String)
    }

    public let notice: Notice
    public private(set) var step: Step = .preparing
    public var pickup: Library? {
        didSet { if oldValue != nil, pickup != oldValue { feedback = .selection } }
    }
    public private(set) var feedback: FeedbackEvent?

    public var isSubmitting: Bool {
        if case .submitting = step { true } else { false }
    }

    @ObservationIgnored @Dependency(\.accountClient) private var account

    public init(notice: Notice, defaultPickup: Library?) {
        self.notice = notice
        self.pickup = defaultPickup
    }

    public func prepare() async {
        step = .preparing
        do {
            let request = try await account.prepareHold(notice.id)
            if pickup == nil || !request.pickupLibraries.contains(pickup!) {
                pickup = request.defaultPickup ?? request.pickupLibraries.first
            }
            step = .choosing(request)
        } catch HoldError.notHoldable {
            step = .failed(.local("Ce document ne peut pas être réservé pour le moment."))
        } catch {
            step = .failed(Self.message(for: error))
        }
    }

    public func submit() async {
        guard case let .choosing(request) = step, let pickup else { return }
        step = .submitting(request)
        do {
            let message = try await account.placeHold(request, pickup)
            step = .confirmed(message: message, pickup: pickup)
            feedback = .success
        } catch let HoldError.refused(message) {
            step = .failed(message)
            feedback = .error
        } catch {
            step = .failed(Self.message(for: error))
            feedback = .error
        }
    }

    static func message(for error: any Error) -> String {
        switch LoadError(error) {
        case .offline: .local("Réservation impossible hors ligne.")
        case .notLoggedIn: .local("Connectez-vous dans l'onglet Compte pour réserver.")
        default: .local("La réservation n'a pas abouti. Réessayez dans un instant.")
        }
    }
}
