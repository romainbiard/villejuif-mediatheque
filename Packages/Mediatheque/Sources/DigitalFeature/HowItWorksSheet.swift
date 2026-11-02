// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import DesignSystem
import SwiftUI

struct HowItWorksSheet: View {
    let offer: DigitalOffer
    let availability: AppAvailability
    let primaryLabel: String
    let primary: () -> Void
    let install: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Text(offer.summary).foregroundStyle(Color.inkSecondary)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(offer.firstUseSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: "\(index + 1)")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.brandViolet, in: Circle())
                                Text(step)
                            }
                        }
                    }

                    if let hint = offer.copyableHint {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.label).font(.footnote).foregroundStyle(Color.inkSecondary)
                                Text(hint.value).font(.title2.weight(.heavy)).monospacedDigit()
                            }
                            Spacer()
                            Button(copied ? LocalizedStringResource.local("Copié") : .local("Copier"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.string = hint.value
                                copied = true
                            }
                            .buttonStyle(.prominent(tint: .brandViolet.opacity(0.14), foreground: .brandVioletDeep))
                            .fixedSize()
                        }
                        .cardStyle()
                    }

                    // Companion app (reader, music, comics): installed or to install, here.
                    if let app = offer.app, app.role != .required {
                        companionRow(app)
                    }

                    Button(action: primary) {
                        Text(primaryLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent(size: .large))

                    Button(.local("Tutoriel complet (PDF)")) { openURL(offer.tutorialURL) }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Color.surfaceGrouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.local("Fermer"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: copied)
    }

    private var header: some View {
        HStack(spacing: 12) {
            let colors = BrandArtwork.colors(for: offer.colorSeed)
            Image(systemName: offer.systemImage)
                .font(.title3)
                .foregroundStyle(BrandArtwork.foreground(for: offer.colorSeed))
                .frame(width: 48, height: 48)
                .background(colors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.category).font(.footnote.weight(.bold)).textCase(.uppercase).foregroundStyle(Color.inkSecondary)
                Text(.local("Comment ça marche")).font(.title2.weight(.heavy))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func companionRow(_ app: ProviderApp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hex: 0x1C1B22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.subheadline.weight(.bold))
                Text(.local("\(app.publisher) · Gratuite")).font(.footnote).foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
            if availability == .installed, let url = app.launchURL {
                Button(.local("Ouvrir")) { openURL(url) }
                    .buttonStyle(.prominent(size: .compact))
                    .fixedSize()
            } else {
                Button(.local("Installer"), action: install)
                    .buttonStyle(.prominent(size: .compact))
                    .fixedSize()
            }
        }
        .cardStyle()
    }
}
#endif
