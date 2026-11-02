// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation
import Security

// MARK: - My selections

@MainActor
@Observable
public final class SelectionsViewModel {
    public private(set) var state: LoadState<[Selection]> = .idle
    public private(set) var isCreating = false
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.profileClient) private var profile

    public init() {}

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await profile.selections())
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public func create(named name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if state.value?.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) == true {
            message = String.local("Une sélection porte déjà ce nom")
            feedback = .error
            return
        }
        isCreating = true
        defer { isCreating = false }
        do {
            try await profile.createSelection(name)
            await load()
            message = String.local("Sélection « \(name) » créée")
            feedback = .success
        } catch {
            message = ProfileMessages.failure(error, action: .creation)
            feedback = .error
        }
    }

    public func dismissMessage() { message = nil }
}

@MainActor
@Observable
public final class SelectionDetailViewModel {
    public let selection: Selection
    public private(set) var state: LoadState<[Notice]> = .idle
    public private(set) var removing: Set<Notice.ID> = []
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.profileClient) private var profile

    public init(selection: Selection) {
        self.selection = selection
    }

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            // Selections stay short: load all pages at once.
            var notices: [Notice] = []
            var page = 1
            while true {
                let result = try await profile.selectionNotices(selection, page)
                notices += result.documents
                guard !result.documents.isEmpty, notices.count < result.total, page < 10 else { break }
                page += 1
            }
            state = .loaded(notices)
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public func remove(_ notice: Notice) async {
        removing.insert(notice.id)
        defer { removing.remove(notice.id) }
        do {
            try await profile.removeFromSelection(selection, notice.id)
            if case let .loaded(notices) = state { state = .loaded(notices.filter { $0.id != notice.id }) }
            message = String.local("Retiré de « \(selection.name) »")
            feedback = .lightImpact
        } catch {
            message = ProfileMessages.failure(error, action: .removal)
            feedback = .error
        }
    }

    public func dismissMessage() { message = nil }
}

// MARK: - My reviews

@MainActor
@Observable
public final class ReviewsViewModel {
    public private(set) var toRate: LoadState<[RecordToRate]> = .idle
    public private(set) var published: LoadState<[Review]> = .idle
    public private(set) var isSubmitting = false
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.profileClient) private var profile

    public init() {}

    public func load() async {
        if toRate.value == nil { toRate = .loading }
        if published.value == nil { published = .loading }
        do {
            toRate = .loaded(try await profile.recordsToRate())
        } catch {
            if toRate.value == nil { toRate = .failed(LoadError(error)) }
        }
        do {
            published = .loaded(try await profile.reviews())
        } catch {
            if published.value == nil { published = .failed(LoadError(error)) }
        }
    }

    /// Submits the review. Returns `true` if the sheet can close.
    public func submit(_ record: RecordToRate, rating: Int, title: String, text: String) async -> Bool {
        guard (1...5).contains(rating) else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await profile.submitReview(record, rating, title.trimmingCharacters(in: .whitespacesAndNewlines), text.trimmingCharacters(in: .whitespacesAndNewlines))
            if case let .loaded(records) = toRate { toRate = .loaded(records.filter { $0.id != record.id }) }
            message = String.local("Merci ! Votre avis sera publié après validation.")
            feedback = .success
            if let reviews = try? await profile.reviews() { published = .loaded(reviews) }
            return true
        } catch {
            message = ProfileMessages.failure(error, action: .sending)
            feedback = .error
            return false
        }
    }

    public func dismissMessage() { message = nil }
}

// MARK: - My suggestions

@MainActor
@Observable
public final class SuggestionsViewModel {
    public var draft = SuggestionDraft()
    public private(set) var sent: LoadState<[Suggestion]> = .idle
    public private(set) var isSending = false
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.profileClient) private var profile

    public init() {}

    public func load() async {
        if sent.value == nil { sent = .loading }
        do {
            sent = .loaded(try await profile.suggestions())
        } catch {
            if sent.value == nil { sent = .failed(LoadError(error)) }
        }
    }

    public func send() async {
        guard draft.isValid, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await profile.sendSuggestion(draft)
            message = String.local("Suggestion envoyée. Merci !")
            feedback = .success
            draft = SuggestionDraft()
            await load()
        } catch {
            message = ProfileMessages.failure(error, action: .sending)
            feedback = .error
        }
    }

    public func dismissMessage() { message = nil }
}

// MARK: - My information

@MainActor
@Observable
public final class InformationViewModel {
    public private(set) var contact: LoadState<ContactDetails> = .idle
    public private(set) var isSaving = false
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?
    /// Shown once the password sheet is gone: the app can't update the Passwords app itself
    /// (the portal publishes no apple-app-site-association file), so the user has to.
    public var showsPasswordsReminder = false
    private var passwordChanged = false

    @ObservationIgnored @Dependency(\.profileClient) private var profile
    @ObservationIgnored @Dependency(\.keychainClient) private var keychain

    public init() {}

    public func load() async {
        if contact.value == nil { contact = .loading }
        do {
            contact = .loaded(try await profile.contactDetails())
        } catch {
            if contact.value == nil { contact = .failed(LoadError(error)) }
        }
    }

    /// Returns `true` if the sheet can close.
    public func save(_ details: ContactDetails) async -> Bool {
        let email = details.email.trimmingCharacters(in: .whitespaces)
        guard email.isEmpty || email.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[^@\s]+/#) != nil else {
            message = String.local("Adresse e-mail invalide")
            feedback = .error
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await profile.updateContactDetails(details)
            contact = .loaded(details)
            message = String.local("Coordonnées enregistrées")
            feedback = .success
            return true
        } catch {
            message = ProfileMessages.failure(error, action: .saving)
            feedback = .error
            return false
        }
    }

    /// Local validation before submitting. `nil` when the new password is acceptable.
    public static func passwordProblem(_ password: String, confirmation: String) -> String? {
        if password.isEmpty { return .local("Saisissez un nouveau mot de passe") }
        if password != confirmation { return .local("Les deux mots de passe ne correspondent pas") }
        return nil
    }

    /// Strong password generated by the system (Safari's generator), offered by the password sheet.
    /// `nil` when the system can't provide one: the button then does nothing.
    public static func suggestedPassword() -> String? {
        SecCreateSharedWebCredentialPassword() as String?
    }

    /// Called when the password sheet is dismissed: raises the Passwords reminder after a change.
    public func passwordSheetDismissed() {
        guard passwordChanged else { return }
        passwordChanged = false
        showsPasswordsReminder = true
    }

    /// Returns `true` if the sheet can close.
    public func changePassword(_ password: String, confirmation: String) async -> Bool {
        if let problem = Self.passwordProblem(password, confirmation: confirmation) {
            message = problem
            feedback = .error
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await profile.changePassword(password)
            // Automatic re-login uses the keychain: store the new password there.
            if let credentials = try? keychain.load() {
                try? keychain.save(Credentials(cardNumber: credentials.cardNumber, password: password))
            }
            passwordChanged = true
            feedback = .success
            return true
        } catch {
            message = ProfileMessages.failure(error, action: .passwordChange)
            feedback = .error
            return false
        }
    }

    public func dismissMessage() { message = nil }
}

// MARK: - My settings

@MainActor
@Observable
public final class ProfileSettingsViewModel {
    public private(set) var bookmarks: LoadState<Set<Library>> = .idle
    public private(set) var newsletter: Bool
    public private(set) var updating: Set<String> = []
    public private(set) var message: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.profileClient) private var profile
    @ObservationIgnored @Dependency(\.notificationClient) private var notifications
    @ObservationIgnored @Dependency(\.biometricClient) private var biometrics

    public init(newsletterSubscribed: Bool) {
        newsletter = newsletterSubscribed
    }

    /// "Face ID" or "Touch ID", `nil` if the device has neither.
    public var biometricKind: String? { biometrics.availableKind() }

    /// After a reminder change: authorization requested on enabling, reminders rescheduled.
    /// Returns `false` if iOS refuses notifications.
    public func remindersChanged(enabling: Bool) async -> Bool {
        if enabling, !(await notifications.requestAuthorization()) {
            message = String.local("Autorisez les notifications dans Réglages pour recevoir les rappels")
            feedback = .error
            return false
        }
        feedback = .lightImpact
        _ = try? await withDependencies(from: self) { try await AccountSync.run(settings: .current()) }
        return true
    }

    public func load() async {
        if bookmarks.value == nil { bookmarks = .loading }
        do {
            bookmarks = .loaded(try await profile.bookmarkedLibraries())
        } catch {
            if bookmarks.value == nil { bookmarks = .failed(LoadError(error)) }
        }
    }

    public func setBookmarked(_ library: Library, _ isOn: Bool) async {
        guard var current = bookmarks.value, current.contains(library) != isOn else { return }
        updating.insert(library.rawValue)
        defer { updating.remove(library.rawValue) }
        do {
            try await profile.setLibraryBookmarked(library, isOn)
            if isOn { current.insert(library) } else { current.remove(library) }
            bookmarks = .loaded(current)
            feedback = .lightImpact
        } catch {
            message = ProfileMessages.failure(error, action: .modification)
            feedback = .error
        }
    }

    public func setNewsletter(_ isOn: Bool) async {
        guard newsletter != isOn else { return }
        updating.insert("newsletter")
        defer { updating.remove("newsletter") }
        do {
            try await profile.setNewsletterSubscribed(isOn)
            newsletter = isOn
            feedback = .lightImpact
        } catch {
            message = ProfileMessages.failure(error, action: .modification)
            feedback = .error
        }
    }

    public func dismissMessage() { message = nil }
}

// MARK: - Messages

enum ProfileMessages {
    /// "L'envoi n'a pas abouti", or the site's message when it rejects the form.
    enum Action { case creation, removal, sending, saving, passwordChange, modification }

    static func failure(_ error: any Error, action: Action) -> String {
        if case let ProfileError.rejected(reason) = error { return reason }
        let offline = LoadError(error) == .offline
        switch action {
        case .creation:
            return offline ? String.local("La création est impossible hors ligne") : String.local("La création n'a pas abouti")
        case .removal:
            return offline ? String.local("Le retrait est impossible hors ligne") : String.local("Le retrait n'a pas abouti")
        case .sending:
            return offline ? String.local("L'envoi est impossible hors ligne") : String.local("L'envoi n'a pas abouti")
        case .saving:
            return offline ? String.local("L'enregistrement est impossible hors ligne") : String.local("L'enregistrement n'a pas abouti")
        case .passwordChange:
            return offline ? String.local("Le changement est impossible hors ligne") : String.local("Le changement n'a pas abouti")
        case .modification:
            return offline ? String.local("La modification est impossible hors ligne") : String.local("La modification n'a pas abouti")
        }
    }
}
