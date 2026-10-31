import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Après la première connexion : explication des notifications (« push primer »),
/// alerte système seulement si l'abonné accepte, puis réglages fins et Face ID.
///
/// iOS n'affiche son alerte qu'une fois dans la vie de l'app : on ne la déclenche
/// qu'après un oui explicite, pour ne pas gaspiller ce seul essai.
@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Step: Equatable {
        /// État des autorisations en cours de lecture.
        case checking
        case primer
        case settings
    }

    public private(set) var step: Step = .checking
    /// Les notifications sont autorisées par iOS : les interrupteurs sont actifs.
    public private(set) var notificationsAllowed = false
    /// Refus (maintenant ou par le passé) : on renvoie vers Réglages plutôt que d'insister.
    public private(set) var notificationsDenied = false
    public private(set) var isRequesting = false
    public private(set) var isFinishing = false
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.notificationClient) private var notifications

    public init() {}

    /// Sans alerte encore demandée, on montre l'explication ; sinon on va droit aux réglages.
    public func start() async {
        switch await notifications.authorizationStatus() {
        case .notDetermined:
            step = .primer
        case .authorized:
            notificationsAllowed = true
            step = .settings
        case .denied:
            notificationsDenied = true
            step = .settings
        }
    }

    /// « Activer les notifications » : c'est seulement ici que l'alerte système apparaît.
    public func enableNotifications() async {
        isRequesting = true
        defer { isRequesting = false }
        let granted = await notifications.requestAuthorization()
        notificationsAllowed = granted
        notificationsDenied = !granted
        feedback = granted ? .success : .lightImpact
        step = .settings
    }

    /// « Pas maintenant » : l'alerte système reste disponible pour plus tard (Mes configurations).
    public func skipNotifications() {
        notificationsAllowed = false
        notificationsDenied = false
        feedback = .lightImpact
        step = .settings
    }

    /// « Terminer » : on applique Face ID, puis on reprogramme les rappels avec les réglages choisis.
    public func finish(faceID: Bool, session: SessionStore) async {
        isFinishing = true
        defer { isFinishing = false }
        session.isFaceIDEnabled = faceID
        _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        feedback = .success
    }
}
