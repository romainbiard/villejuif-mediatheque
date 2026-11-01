// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Loading state, exposed by the ViewModels.
public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(LoadError)

    public var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension LoadState: Equatable where Value: Equatable {}

/// Error that can be shown on screen.
public enum LoadError: Error, Equatable, Sendable {
    case offline
    case siteUnavailable
    case notLoggedIn
    case other(String)

    public init(_ error: any Error) {
        switch error {
        case let urlError as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(urlError.code):
            self = .offline
        case is URLError:
            self = .siteUnavailable
        case AuthError.notLoggedIn, AuthError.invalidCredentials:
            self = .notLoggedIn
        default:
            self = .other(String(describing: error))
        }
    }
}

/// Haptic feedback to trigger, wired by the view to `.sensoryFeedback`.
public enum FeedbackEvent: Hashable, Sendable {
    case success
    case error
    case selection
    case lightImpact
}
