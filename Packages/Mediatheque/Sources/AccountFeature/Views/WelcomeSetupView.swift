// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DesignSystem
import MediathequeCore
import SwiftUI

/// After the first sign-in: notifications explanation, system alert on a yes,
/// then fine-grained settings (notifications, Face ID). Everything can be changed later in "Mes configurations".
struct WelcomeSetupView: View {
    let patron: Patron
    let done: () -> Void

    @State private var viewModel = OnboardingViewModel()
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch viewModel.step {
            case .checking:
                Color.brandViolet.ignoresSafeArea()
            case .primer:
                NotificationPrimerView(viewModel: viewModel)
                    .transition(.opacity)
            case .settings:
                OnboardingSettingsView(viewModel: viewModel) { faceID in
                    Task {
                        await viewModel.finish(faceID: faceID, session: session)
                        done()
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: viewModel.step)
        .task { await viewModel.start() }
        .interactiveDismissDisabled()
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }
}

// MARK: - Explanation (push primer)

/// Reuses the sign-in layout: purple background, brand shapes, card at the bottom.
struct NotificationPrimerView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                NotificationPreview(text: "« Sway » est à rendre jeudi", time: "maintenant")
                NotificationPreview(text: "« Murmuration » vous attend à Elsa-Triolet", time: "9:12")
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 520, maxHeight: .infinity)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Ne ratez plus un retour")
                    .font(.title.bold())
                    .foregroundStyle(Color.ink)
                Text("Un rappel trois jours avant chaque date de retour, et une alerte dès qu'une réservation vous attend. Rien d'autre.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                VStack(spacing: 10) {
                    Button {
                        Task { await viewModel.enableNotifications() }
                    } label: {
                        Text("Activer les notifications").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent(size: .large, isLoading: viewModel.isRequesting))
                    .disabled(viewModel.isRequesting)

                    Button {
                        viewModel.skipNotifications()
                    } label: {
                        Text("Pas maintenant").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent(tint: .soft(.brandViolet), foreground: .brandVioletDeep, size: .large))
                    .disabled(viewModel.isRequesting)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 18)
            .background(Color.surfaceCard, in: ConcentricRectangle(corners: .concentric, isUniform: true))
            .padding(10)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .background { BrandBackdrop() }
    }
}

/// Sample notification banner, in glass, with the app's real icon.
struct NotificationPreview: View {
    let text: String
    let time: String

    var body: some View {
        HStack(spacing: 10) {
            VillejuifLogo.crest
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(6)
                .frame(width: 34, height: 34)
                .background(Color.brandMagenta, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Ma médiathèque").font(.footnote.weight(.semibold))
                    Spacer()
                    Text(time).font(.caption).foregroundStyle(.secondary)
                }
                Text(text).font(.footnote).lineLimit(2)
            }
        }
        .foregroundStyle(Color(hex: 0x1C1B22))
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.55)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Brand shapes, pushed into the corners so they never sit under the content.
struct BrandBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.brandViolet
                Circle().fill(Color.brandMagenta)
                    .frame(width: 330)
                    .offset(x: proxy.size.width - 165, y: -190)
                Circle().fill(Color.brandVioletDeep)
                    .frame(width: 190)
                    .offset(x: -120, y: proxy.size.height * 0.5)
                Circle().fill(Color.brandYellow)
                    .frame(width: 16)
                    .offset(x: 44, y: proxy.safeAreaInsets.top + 64)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Fine-grained settings

struct OnboardingSettingsView: View {
    let viewModel: OnboardingViewModel
    let finish: (_ faceID: Bool) -> Void

    @AppStorage(ReminderSettings.Key.loanReminders, store: .shared) private var loanReminders = true
    @AppStorage(ReminderSettings.Key.holdAlerts, store: .shared) private var holdAlerts = true
    @AppStorage(ReminderSettings.Key.agendaDigest, store: .shared) private var agendaDigest = false
    @State private var faceID = false
    @Environment(\.openURL) private var openURL
    private let biometricKind: String?

    init(viewModel: OnboardingViewModel, finish: @escaping (_ faceID: Bool) -> Void) {
        self.viewModel = viewModel
        self.finish = finish
        @Dependency(\.biometricClient) var biometrics
        biometricKind = biometrics.availableKind()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Vos réglages").font(.largeTitle.bold())
                Text("Modifiables à tout moment dans Mes configurations.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 4)

                SectionHeader("Notifications").padding(.top, 24).padding(.bottom, 8)
                if viewModel.notificationsAllowed {
                    SettingsCard {
                        SettingRow("Rappels de retour", detail: "3 jours avant et le jour J",
                                   systemImage: "calendar.badge.clock", tint: .brandMagenta, isOn: $loanReminders)
                        SettingRow("Réservations", detail: "Dès qu'un document arrive",
                                   systemImage: "shippingbox.fill", tint: .statusSuccess, isOn: $holdAlerts)
                        SettingRow("Agenda", detail: "Les animations du lundi",
                                   systemImage: "calendar", tint: .brandVioletDeep, isOn: $agendaDigest)
                    }
                } else {
                    notificationsOff
                }

                if let biometricKind {
                    SectionHeader("Sécurité").padding(.top, 24).padding(.bottom, 8)
                    SettingsCard {
                        SettingRow(biometricKind, detail: "Sans mot de passe",
                                   systemImage: biometricKind == "Touch ID" ? "touchid" : "faceid",
                                   tint: Color(hex: 0x1C1B22), isOn: $faceID)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color.surfaceGrouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                finish(faceID)
            } label: {
                Text("Terminer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent(size: .large, isLoading: viewModel.isFinishing))
            .disabled(viewModel.isFinishing)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: 600)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: [loanReminders, holdAlerts, agendaDigest, faceID])
    }

    /// Denied or "Pas maintenant": no inert toggles, but an explanation and the steps to follow.
    private var notificationsOff: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 32, height: 32)
                .background(Color.soft(.inkSecondary), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications désactivées").font(.subheadline.weight(.semibold))
                Text(viewModel.notificationsDenied
                    ? "Pour recevoir les rappels de retour, autorisez les notifications dans Réglages."
                    : "Vous pourrez les activer plus tard dans Mes configurations.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.notificationsDenied {
                    Button("Ouvrir Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// iOS 26-style grouped card: 22 pt corners, separators aligned with the text.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 { Divider().padding(.leading, 56) }
                }
            }
        }
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SettingRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    init(_ title: String, detail: String, systemImage: String, tint: Color, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                    Text(detail).font(.footnote).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .tint(.brandViolet)
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }
}


/// Face ID is enabled: the account opens after authentication.
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
                .buttonStyle(.prominent(tint: .white, foreground: .brandViolet))
            Button("Se déconnecter") { Task { await session.logout() } }
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.brandViolet.ignoresSafeArea())
    }
}
