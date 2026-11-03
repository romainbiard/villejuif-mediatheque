// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

struct LibraryCardView: View {
    let patron: Patron
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // "Gratuit" next to the name, under it at accessibility text sizes (the name would wrap mid-word).
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top))
        VStack(alignment: .leading, spacing: 14) {
            header {
                VStack(alignment: .leading, spacing: 8) {
                    VillejuifLogo.white.resizable().scaledToFit().frame(height: 26).accessibilityLabel(Text(.local("Ville de Villejuif")))
                    Text(patron.displayName).font(.title2.weight(.bold))
                    if let expiry = patron.cardExpiry {
                        Text(.local("Carte valable jusqu'au \(expiry.parisFormatted(.dateTime.day().month(.wide).year()))"))
                            .font(.footnote)
                            .opacity(0.85)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(.local("Gratuit"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 6) {
                BarcodeView(value: patron.cardNumber).frame(height: 44)
                let footer = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout())
                footer {
                    Text(patron.cardNumber).font(.footnote.weight(.semibold)).monospacedDigit().tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(.local("Toucher pour agrandir")).font(.footnote).foregroundStyle(Color(hex: 0x5E5B66))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color(hex: 0x1C1B22))
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            ZStack {
                Color.brandVioletSurface
                Circle().fill(Color.brandMagenta.opacity(0.55)).frame(width: 220).offset(x: 140, y: -110)
                Circle().fill(Color.brandVioletDeep.opacity(0.7)).frame(width: 120).offset(x: 170, y: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.local("Carte d'abonné de \(patron.displayName), numéro \(patron.cardNumber)")))
    }
}

/// Full-screen card for the front desk, brightness at maximum while it is displayed.
///
/// The barcode is vertical, against the right edge and the same size as the one on the plastic card:
/// any larger and it overflows the handheld scanner's window; at the edge, the phone can get close to the reader.
/// When the right edge holds the camera and status bar (iPhone Duo), the barcode moves to the left edge.
struct FullScreenCardView: View {
    let patron: Patron
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat?
    /// The right edge has a safe-area inset and not the left one: barcode against the left edge.
    /// iPhone in portrait and iPad have no side inset, so they keep the right edge.
    @State private var barcodeOnLeading = false
    /// Barcode orientation chosen by the patron (depending on the reader), remembered between displays.
    @AppStorage("card.barcodeFlipped") private var isFlipped = true

    /// About 43 × 11 mm on iPhone, like the barcode printed on the card.
    static let barcodeLength: CGFloat = 260
    static let barcodeThickness: CGFloat = 64
    static let edgeInset: CGFloat = 14

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            HStack(spacing: 0) {
                if barcodeOnLeading {
                    barcode
                    Spacer(minLength: 16)
                    identity
                } else {
                    identity
                    Spacer(minLength: 16)
                    barcode
                }
            }
            .padding(.leading, barcodeOnLeading ? Self.edgeInset : 24)
            .padding(.trailing, barcodeOnLeading ? 24 : Self.edgeInset)
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.safeAreaInsets.trailing > proxy.safeAreaInsets.leading
        } action: { barcodeOnLeading = $0 }
        .overlay(alignment: barcodeOnLeading ? .leading : .trailing) {
            // Marker for the edge to present to the reader.
            UnevenRoundedRectangle(
                topLeadingRadius: barcodeOnLeading ? 0 : 2,
                bottomLeadingRadius: barcodeOnLeading ? 0 : 2,
                bottomTrailingRadius: barcodeOnLeading ? 2 : 0,
                topTrailingRadius: barcodeOnLeading ? 2 : 0
            )
            .fill(Color.brandViolet.opacity(0.35))
            .frame(width: 4, height: Self.barcodeLength)
            .ignoresSafeArea(edges: barcodeOnLeading ? .leading : .trailing)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            Button(.local("Fermer"), systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button(.local("Pivoter le code-barres"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                withAnimation(.smooth(duration: 0.35)) { isFlipped.toggle() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(.trailing, 20)
            .padding(.top, 8)
            .sensoryFeedback(.selection, trigger: isFlipped)
        }
        .overlay(alignment: .bottom) { hint }
        .foregroundStyle(Color(hex: 0x1C1B22))
        .onAppear(perform: brighten)
        .onDisappear(perform: restore)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.local("Carte d'abonné"))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.brandViolet)
            Text(patron.displayName).font(.title.weight(.heavy))
            Text(.local("Médiathèques de Villejuif")).font(.subheadline).foregroundStyle(Color(hex: 0x5E5B66))
            Text(.local("N° de carte"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: 0x5E5B66))
                .padding(.top, 18)
            Text(patron.cardNumber)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let expiry = patron.cardExpiry {
                Text(.local("Valable jusqu'au \(expiry.parisFormatted(.dateTime.day().month(.wide).year()))"))
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x5E5B66))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var barcode: some View {
        HStack(spacing: 8) {
            // Human-readable number along the barcode, read bottom to top as on the card.
            Text(verbatim: "*\(patron.cardNumber)*")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .tracking(4)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.barcodeLength)
                .rotationEffect(.degrees(-90))
                .frame(width: 16, height: Self.barcodeLength)
                .accessibilityHidden(true)
            BarcodeView(value: patron.cardNumber, axis: .vertical)
                .frame(width: Self.barcodeThickness, height: Self.barcodeLength)
        }
        // Rotated a half turn by default: the number moves to the edge side and reads top to bottom.
        // Against the left edge, the default is the other way round, so the number stays on the edge side.
        .rotationEffect(.degrees(isFlipped != barcodeOnLeading ? 180 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.local("Code-barres de la carte, numéro \(patron.cardNumber)")))
    }

    private var hint: some View {
        HStack(spacing: 12) {
            Image(systemName: barcodeOnLeading ? "arrow.left" : "arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.brandViolet, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(.local("Approchez ce bord du lecteur")).font(.subheadline.weight(.semibold))
                Text(.local("Luminosité au maximum pendant l'affichage"))
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x5E5B66))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: 0xF4F3F8), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func brighten() {
        #if canImport(UIKit)
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
        #endif
    }

    private func restore() {
        #if canImport(UIKit)
        guard let previousBrightness,
              let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first
        else { return }
        screen.brightness = previousBrightness
        #endif
    }
}

/// Barcode of the card number, in Code 39 like the plastic card (read by handheld scanners).
/// In `.vertical`, it reads top to bottom.
struct BarcodeView: View {
    let value: String
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    /// Wide/narrow ratio: 3 is the standard's maximum and the most forgiving to read.
    static let wideRatio = 3.0

    var body: some View {
        Canvas { context, size in
            guard let elements = Code39.elements(for: value) else { return }
            let isVertical = axis == .vertical
            let length = isVertical ? size.height : size.width
            let total = Code39.width(of: elements, wideRatio: Self.wideRatio)
            // Narrow module snapped to a whole number of pixels: crisp bars, no blur.
            let module = max(1, (length * displayScale / total).rounded(.down)) / displayScale
            var position = (length - module * total) / 2
            for element in elements {
                let width = module * (element.isWide ? Self.wideRatio : 1)
                if element.isBar {
                    let rect = isVertical
                        ? CGRect(x: 0, y: position, width: size.width, height: width)
                        : CGRect(x: position, y: 0, width: width, height: size.height)
                    context.fill(Path(rect), with: .color(.black))
                }
                position += width
            }
        }
        .accessibilityHidden(true)
    }
}

struct CardExpiryBanner: View {
    let patron: Patron

    var body: some View {
        Label(
            patron.cardExpired
                ? String.local("Votre carte a expiré. Renouvelez-la à l'accueil d'une médiathèque.")
                : String.local("Votre carte expire dans \(patron.cardExpiresInDays) jours. Renouvelez-la à l'accueil."),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(patron.cardExpired ? Color.statusDanger : Color.statusWarning)
        .cardStyle()
    }
}
