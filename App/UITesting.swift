// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if DEBUG
import Dependencies
import Foundation
import MediathequeCore

/// Launch mode for the UI tests (Debug builds only, never in TestFlight): the preview data
/// (fictional patron, sample loans and records) instead of the portal, so the tests need
/// neither network nor a real account, and always see the same screens.
enum UITesting {
    /// Turns the mode on.
    static let argument = "-uiTesting"
    /// Starts signed out (sign-in screen).
    static let signedOutArgument = "-uiTestingSignedOut"
    /// Shows the first sign-in walkthrough instead of marking it as done.
    static let onboardingArgument = "-uiTestingOnboarding"

    static func configureIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(argument) else { return }
        let signedOut = arguments.contains(signedOutArgument)
        prepareDependencies {
            $0.context = .preview
            if signedOut { $0.authClient.restore = { nil } }
        }
        UserDefaults.shared.set(!arguments.contains(onboardingArgument), forKey: ReminderSettings.Key.onboardingDone)
    }
}
#endif
