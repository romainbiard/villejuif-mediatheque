// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import AccountFeature

@MainActor
struct OnboardingViewModelTests {
    private func makeViewModel(
        status: NotificationAuthorization,
        grants: Bool = true,
        requests: LockIsolated<Int> = LockIsolated(0)
    ) -> OnboardingViewModel {
        withDependencies {
            $0.notificationClient.authorizationStatus = { status }
            $0.notificationClient.requestAuthorization = {
                requests.withValue { $0 += 1 }
                return grants
            }
        } operation: {
            OnboardingViewModel()
        }
    }

    @Test func primerIsShownOnlyWhileTheSystemAlertIsStillAvailable() async {
        let fresh = makeViewModel(status: .notDetermined)
        await fresh.start()
        #expect(fresh.step == .primer)

        let allowed = makeViewModel(status: .authorized)
        await allowed.start()
        #expect(allowed.step == .settings)
        #expect(allowed.notificationsAllowed)

        let denied = makeViewModel(status: .denied)
        await denied.start()
        #expect(denied.step == .settings)
        #expect(denied.notificationsDenied)
        #expect(!denied.notificationsAllowed)
    }

    @Test func systemAlertIsRequestedOnlyAfterTheUserAccepts() async {
        let requests = LockIsolated(0)
        let viewModel = makeViewModel(status: .notDetermined, grants: true, requests: requests)
        await viewModel.start()
        #expect(requests.value == 0)

        await viewModel.enableNotifications()
        #expect(requests.value == 1)
        #expect(viewModel.step == .settings)
        #expect(viewModel.notificationsAllowed)
        #expect(viewModel.feedback == .success)
    }

    @Test func refusingTheSystemAlertLeadsToSettingsWithTheDeniedState() async {
        let viewModel = makeViewModel(status: .notDetermined, grants: false)
        await viewModel.start()
        await viewModel.enableNotifications()
        #expect(viewModel.step == .settings)
        #expect(!viewModel.notificationsAllowed)
        #expect(viewModel.notificationsDenied)
    }

    @Test func notNowSkipsTheSystemAlertEntirely() async {
        let requests = LockIsolated(0)
        let viewModel = makeViewModel(status: .notDetermined, requests: requests)
        await viewModel.start()
        viewModel.skipNotifications()
        #expect(requests.value == 0)
        #expect(viewModel.step == .settings)
        #expect(!viewModel.notificationsAllowed)
        #expect(!viewModel.notificationsDenied)
    }
}
