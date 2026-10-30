import Dependencies
import DesignSystem
import MediathequeCore
import SwiftUI

/// Après la première connexion : Face ID et rappels. Modifiable ensuite dans Réglages.
struct WelcomeSetupView: View {
    let patron: Patron
    let done: () -> Void

    @Environment(SessionStore.self) private var session
    @AppStorage(ReminderSettings.Key.loanReminders, store: .shared) private var loanReminders = true
    @AppStorage(ReminderSettings.Key.holdAlerts, store: .shared) private var holdAlerts = true
    @State private var faceID = false
    @State private var isSaving = false
    private let biometricKind: String?

    init(patron: Patron, done: @escaping () -> Void) {
        self.patron = patron
        self.done = done
        @Dependency(\.biometricClient) var biometrics
        biometricKind = biometrics.availableKind()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bonjour \(patron.firstName)").font(.largeTitle.weight(.heavy))
                        Text("Votre compte lecteur est connecté. Encore deux réglages, modifiables à tout moment.")
                            .foregroundStyle(Color.inkSecondary)
                    }
                    VStack(spacing: 0) {
                        if let biometricKind {
                            toggle(biometricKind, detail: "Ouvrir votre compte sans mot de passe", systemImage: "faceid", tint: .brandViolet, isOn: $faceID)
                            Divider().padding(.leading, 62)
                        }
                        toggle("Rappels de retour", detail: "3 jours avant, puis le jour même", systemImage: "bell.badge", tint: .statusDanger, isOn: $loanReminders)
                        Divider().padding(.leading, 62)
                        toggle("Réservations", detail: "Quand un document vous attend", systemImage: "shippingbox", tint: .statusSuccess, isOn: $holdAlerts)
                    }
                    .cardStyle(padding: 0)
                }
                .padding(20)
            }
            .background(Color.surfaceGrouped)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving { ProgressView().tint(.white) } else { Text("Continuer") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandViolet)
                .controlSize(.extraLarge)
                .padding(16)
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.impact(weight: .light), trigger: [faceID, loanReminders, holdAlerts])
    }

    private func toggle(_ title: String, detail: String, systemImage: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Color.soft(tint), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .tint(.brandViolet)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        @Dependency(\.notificationClient) var notifications
        session.isFaceIDEnabled = faceID
        if loanReminders || holdAlerts {
            let granted = await notifications.requestAuthorization()
            if !granted {
                loanReminders = false
                holdAlerts = false
            }
        }
        _ = try? await AccountSync.run(settings: .current())
        done()
    }
}

/// Face ID est activé : le compte s'ouvre après validation.
struct LockedView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            Text("Compte verrouillé").font(.title.weight(.heavy)).foregroundStyle(.white)
            Button("Déverrouiller") { Task { await session.unlock() } }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(Color.brandViolet)
                .controlSize(.extraLarge)
            Button("Se déconnecter") { Task { await session.logout() } }
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.brandViolet.ignoresSafeArea())
    }
}
