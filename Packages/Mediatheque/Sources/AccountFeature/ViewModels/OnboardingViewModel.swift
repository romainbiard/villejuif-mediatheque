// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// After the first sign-in: notifications explanation ("push primer"),
/// system alert only if the patron accepts, then fine-grained settings and Face ID.
///
/// iOS shows its alert only once in the app's lifetime: we trigger it only
/// after an explicit yes, so as not to waste that single attempt.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Equatable {
        /// Authorization status being read.
        case checking
        case primer
        case settings
    }

    private(set) var step: Step = .checking
    /// Notifications are allowed by iOS: the toggles are enabled.
    private(set) var notificationsAllowed = false
    /// Denied (now or in the past): point to Settings rather than insisting.
    private(set) var notificationsDenied = false
    private(set) var isRequesting = false
    private(set) var isFinishing = false
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.notificationClient) private var notifications

    init() {}

    /// If no alert has been requested yet, show the explanation; otherwise go straight to the settings.
    func start() async {
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

    /// "Activer les notifications": this is the only place where the system alert appears.
    func enableNotifications() async {
        isRequesting = true
        defer { isRequesting = false }
        let granted = await notifications.requestAuthorization()
        notificationsAllowed = granted
        notificationsDenied = !granted
        feedback = granted ? .success : .lightImpact
        step = .settings
    }

    /// "Pas maintenant": the system alert stays available for later ("Mes configurations").
    func skipNotifications() {
        notificationsAllowed = false
        notificationsDenied = false
        feedback = .lightImpact
        step = .settings
    }

    /// "Terminer": apply Face ID, then reschedule reminders with the chosen settings.
    func finish(faceID: Bool, session: SessionStore) async {
        isFinishing = true
        defer { isFinishing = false }
        session.isFaceIDEnabled = faceID
        _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        feedback = .success
    }
}
