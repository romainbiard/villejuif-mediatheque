// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import DesignSystem
import StoreKit
import SwiftUI
import UIKit

/// "Regardez vos films dans l'app": introduces the partner's app before the App Store sheet.
/// It only appears if the app is not installed; when installed, the app opens directly.
struct InstallAppSheet: View {
    let offer: DigitalOffer
    let app: ProviderApp
    let get: () -> Void
    let continueOnWeb: () -> Void
    @State private var contentHeight: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: offer.systemImage)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color(hex: 0x17161C), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title3.weight(.heavy))
                    Text(app.publisher).font(.subheadline).foregroundStyle(Color.inkSecondary)
                    Text("Gratuite · iPhone et iPad").font(.footnote).foregroundStyle(Color.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            Text(title)
                .font(.title2.weight(.heavy))
                .padding(.top, 22)
            Text("\(offer.provider) a sa propre app. Installez-la une fois : Ma médiathèque vous y connecte ensuite à chaque fois.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            if !app.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(app.highlights, id: \.self) { highlight in
                        Label {
                            Text(highlight.text).font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: highlight.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.brandVioletDeep)
                                .frame(width: 32, height: 32)
                                .background(Color.brandViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(.top, 18)
            }

            Button(action: get) {
                Label("Obtenir l'app", systemImage: "arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent(size: .large))
            .padding(.top, 24)

            Button("Continuer dans le navigateur", action: continueOnWeb)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch offer.id {
        case "films": "Regardez vos films dans l'app"
        case "presse": "Lisez la presse dans l'app"
        case "formation": "Suivez vos cours dans l'app"
        default: "Profitez-en dans l'app"
        }
    }
}

/// In-app App Store sheet (`SKStoreProductViewController`): the patron installs without leaving Ma médiathèque.
@MainActor
enum AppStorePresenter {
    @MainActor
    private final class Delegate: NSObject, @preconcurrency SKStoreProductViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
            viewController.dismiss(animated: true)
            onDismiss()
            AppStorePresenter.delegate = nil
        }
    }

    /// The controller does not retain its delegate.
    private static var delegate: Delegate?

    static func present(appStoreID: String, onDismiss: @escaping () -> Void) {
        guard let presenter = topViewController() else {
            onDismiss()
            return
        }
        let delegate = Delegate(onDismiss: onDismiss)
        self.delegate = delegate
        let store = SKStoreProductViewController()
        store.delegate = delegate
        store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: appStoreID]) { loaded, _ in
            guard !loaded else { return }
            // Product not found (offline, App Store unavailable): fall back to the App Store app.
            Task { @MainActor in
                store.dismiss(animated: true)
                if let url = URL(string: "https://apps.apple.com/fr/app/id\(appStoreID)") {
                    await UIApplication.shared.open(url)
                }
                AppStorePresenter.delegate = nil
                onDismiss()
            }
        }
        presenter.present(store, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif
