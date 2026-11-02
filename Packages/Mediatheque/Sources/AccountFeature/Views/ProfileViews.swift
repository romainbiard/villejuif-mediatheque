// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

// MARK: - My information

struct InformationView: View {
    let patron: Patron
    @State private var viewModel = InformationViewModel()
    @State private var editsContact = false
    @State private var changesPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(.local("Abonnement"))
                    VStack(spacing: 0) {
                        InfoRow(label: .local("Numéro de carte"), value: patron.cardNumber, monospaced: true)
                        Divider().padding(.leading, 14)
                        InfoRow(label: .local("Valable jusqu'au"), value: patron.cardExpiry?.formatted(.dateTime.day().month(.wide).year()) ?? "—")
                        Divider().padding(.leading, 14)
                        InfoRow(label: .local("Médiathèque d'inscription"), value: patron.homeLibrary?.name ?? "—")
                    }
                    .cardStyle(padding: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(.local("Coordonnées")) {
                        if viewModel.contact.value != nil {
                            Button(.local("Modifier")) { editsContact = true }.font(.subheadline.weight(.semibold))
                        }
                    }
                    contact
                    Text(.local("Le nom et l'adresse se changent à l'accueil d'une médiathèque, avec un justificatif."))
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(.local("Sécurité"))
                    Button { changesPassword = true } label: {
                        MenuRow(title: .local("Changer le mot de passe"), systemImage: "key.fill", tint: .brandVioletDeep) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .cardStyle(padding: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .readableContentWidth()
        .background(Color.surfaceGrouped)
        .navigationTitle(Text(.local("Mes informations")))
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $editsContact) {
            if let details = viewModel.contact.value {
                ContactEditSheet(details: details, isSaving: viewModel.isSaving) { await viewModel.save($0) }
            }
        }
        .sheet(isPresented: $changesPassword, onDismiss: viewModel.passwordSheetDismissed) {
            PasswordSheet(cardNumber: patron.cardNumber, isSaving: viewModel.isSaving) {
                await viewModel.changePassword($0, confirmation: $1)
            }
        }
        .alert(Text(.local("Mot de passe modifié")), isPresented: $viewModel.showsPasswordsReminder) {
            Button(.local("OK")) {}
        } message: {
            Text(.local("Pensez à le mettre à jour aussi dans l'app Mots de passe : le site de la médiathèque ne permet pas à l'app de le faire pour vous."))
        }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var contact: some View {
        let details = viewModel.contact.value
        VStack(spacing: 0) {
            InfoRow(label: .local("Nom"), value: patron.displayName)
            Divider().padding(.leading, 14)
            InfoRow(label: .local("Pseudo"), value: (details?.nickname ?? patron.nickname ?? "").isEmpty ? "—" : (details?.nickname ?? patron.nickname ?? ""))
            Divider().padding(.leading, 14)
            InfoRow(label: .local("E-mail"), value: details?.email ?? patron.email ?? "—")
            Divider().padding(.leading, 14)
            InfoRow(label: .local("Téléphone"), value: details?.phone ?? patron.phone ?? "—")
            Divider().padding(.leading, 14)
            InfoRow(label: .local("Adresse"), value: patron.postalAddress ?? "—")
            if let details {
                Divider().padding(.leading, 14)
                InfoRow(label: .local("Me contacter par"), value: details.channel.label)
            }
        }
        .redacted(reason: viewModel.contact.isLoading ? .placeholder : [])
        .cardStyle(padding: 0)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .tracking(monospaced ? 1 : 0)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct ContactEditSheet: View {
    let isSaving: Bool
    let save: (ContactDetails) async -> Bool
    @State private var details: ContactDetails
    @Environment(\.dismiss) private var dismiss

    init(details: ContactDetails, isSaving: Bool, save: @escaping (ContactDetails) async -> Bool) {
        self.isSaving = isSaving
        self.save = save
        _details = State(initialValue: details)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $details.nickname) { Text(.local("Pseudo")) }
                        .textContentType(.nickname)
                } footer: {
                    Text(.local("Affiché avec vos avis."))
                }
                Section {
                    TextField(text: $details.email) { Text(.local("E-mail")) }
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(text: $details.phone) { Text(.local("Téléphone")) }
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } header: {
                    Text(.local("Coordonnées"))
                }
                Section {
                    Picker(selection: $details.channel) {
                        ForEach(SendingChannel.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Text(.local("Me contacter par"))
                    }
                } footer: {
                    Text(.local("Pour les avis de réservation disponible et les rappels de la médiathèque."))
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(Text(.local("Coordonnées")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.local("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(.local("Enregistrer")) { Task { if await save(details) { dismiss() } } }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: details.channel)
    }
}

struct PasswordSheet: View {
    let cardNumber: String
    let isSaving: Bool
    let change: (String, String) async -> Bool
    @State private var password = ""
    @State private var confirmation = ""
    @State private var reveals = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Username of the account being changed, as AutoFill expects in a change-password form.
                    TextField(text: .constant(cardNumber)) { Text(.local("Numéro de carte")) }
                        .textContentType(.username)
                        .monospacedDigit()
                        .foregroundStyle(Color.inkSecondary)
                        .disabled(true)
                    passwordField(.local("Nouveau mot de passe"), text: $password)
                    passwordField(.local("Confirmer"), text: $confirmation)
                } footer: {
                    if !confirmation.isEmpty, password != confirmation {
                        Text(.local("Les deux mots de passe ne correspondent pas.")).foregroundStyle(Color.statusDanger)
                    } else {
                        Text(.local("L'app retient le nouveau mot de passe pour vous reconnecter. Mettez-le aussi à jour dans l'app Mots de passe."))
                    }
                }
                Section {
                    // The portal isn't associated with the app, so iOS doesn't offer its own suggestion
                    // in the keyboard: the button asks the system generator for one.
                    Button(.local("Suggérer un mot de passe fort"), systemImage: "key.viewfinder") {
                        guard let suggestion = InformationViewModel.suggestedPassword() else { return }
                        password = suggestion
                        confirmation = suggestion
                        reveals = true
                    }
                    Toggle(.local("Afficher le mot de passe"), isOn: $reveals)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(Text(.local("Mot de passe")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.local("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(.local("Valider")) { Task { if await change(password, confirmation) { dismiss() } } }
                            .disabled(InformationViewModel.passwordProblem(password, confirmation: confirmation) != nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func passwordField(_ title: LocalizedStringResource, text: Binding<String>) -> some View {
        if reveals {
            TextField(text: text) { Text(title) }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .monospaced()
        } else {
            SecureField(text: text) { Text(title) }
                .textContentType(.newPassword)
        }
    }
}

// MARK: - My settings

struct ProfileSettingsView: View {
    let patron: Patron
    @State private var viewModel: ProfileSettingsViewModel
    @AppStorage(ReminderSettings.Key.loanReminders, store: .shared) private var loanReminders = true
    @AppStorage(ReminderSettings.Key.holdAlerts, store: .shared) private var holdAlerts = true
    @AppStorage(ReminderSettings.Key.agendaDigest, store: .shared) private var agendaDigest = false
    /// Same key as `SessionStore.isFaceIDEnabled`, observed by SwiftUI.
    @AppStorage(ReminderSettings.Key.faceID, store: .shared) private var faceID = false

    init(patron: Patron) {
        self.patron = patron
        _viewModel = State(initialValue: ProfileSettingsViewModel(newsletterSubscribed: patron.newsletterSubscribed))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group(.local("Médiathèques préférées"), footer: .local("Mises en avant dans la recherche et l'agenda.")) {
                    libraries
                }
                group(.local("Notifications"), footer: nil) {
                    SettingToggleRow(title: .local("Rappels de retour"), detail: .local("3 jours avant, puis le jour même"), systemImage: "bell.badge", tint: .statusDanger, isOn: reminderBinding($loanReminders))
                    Divider().padding(.leading, 62)
                    SettingToggleRow(title: .local("Réservations disponibles"), detail: .local("Quand un document vous attend"), systemImage: "shippingbox", tint: .statusSuccess, isOn: reminderBinding($holdAlerts))
                    Divider().padding(.leading, 62)
                    SettingToggleRow(title: .local("Agenda de la semaine"), detail: .local("Les animations, le lundi matin"), systemImage: "calendar", tint: .brandVioletDeep, isOn: reminderBinding($agendaDigest))
                }
                group(.local("Lettre d'information"), footer: .local("L'actualité du réseau des médiathèques, par e-mail.")) {
                    SettingToggleRow(
                        title: .local("Recevoir la lettre"),
                        detail: patron.email ?? .local("Adresse e-mail à renseigner"),
                        systemImage: "envelope.open",
                        tint: .brandVioletDeep,
                        isOn: Binding(get: { viewModel.newsletter }, set: { isOn in Task { await viewModel.setNewsletter(isOn) } }),
                        isBusy: viewModel.updating.contains("newsletter")
                    )
                }
                if let biometricKind = viewModel.biometricKind {
                    group(.local("Sécurité"), footer: .local("Le compte s'ouvre après validation, même si l'app reste connectée.")) {
                        SettingToggleRow(
                            title: .local("Verrouiller avec \(biometricKind)"),
                            detail: .local("Protège l'accès à votre compte"),
                            systemImage: "faceid",
                            tint: .brandViolet,
                            isOn: $faceID
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .readableContentWidth()
        .background(Color.surfaceGrouped)
        .navigationTitle(Text(.local("Mes configurations")))
        .task { await viewModel.load() }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
        .sensoryFeedback(.impact(weight: .light), trigger: faceID)
    }

    @ViewBuilder
    private var libraries: some View {
        let bookmarks = viewModel.bookmarks.value ?? []
        ForEach(Library.allCases) { library in
            SettingToggleRow(
                title: library.name,
                detail: library == patron.homeLibrary ? String.local("Votre médiathèque d'inscription") : nil,
                systemImage: "building.columns",
                tint: .brandViolet,
                isOn: Binding(get: { bookmarks.contains(library) }, set: { isOn in Task { await viewModel.setBookmarked(library, isOn) } }),
                isBusy: viewModel.updating.contains(library.rawValue)
            )
            .disabled(viewModel.bookmarks.value == nil)
            if library != Library.allCases.last { Divider().padding(.leading, 62) }
        }
        .redacted(reason: viewModel.bookmarks.isLoading ? .placeholder : [])
    }

    /// Local reminder setting: reschedule, and revert if iOS refuses.
    private func reminderBinding(_ storage: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { storage.wrappedValue },
            set: { isOn in
                storage.wrappedValue = isOn
                Task {
                    if !(await viewModel.remindersChanged(enabling: isOn)) { storage.wrappedValue = false }
                }
            }
        )
    }

    private func group<Content: View>(_ title: String, footer: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            VStack(spacing: 0, content: content).cardStyle(padding: 0)
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(Color.inkSecondary)
            }
        }
    }
}

struct SettingToggleRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool
    var isBusy = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Color.soft(tint), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                if isBusy { ProgressView().padding(.leading, 4) }
            }
        }
        .tint(.brandViolet)
        .disabled(isBusy)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
