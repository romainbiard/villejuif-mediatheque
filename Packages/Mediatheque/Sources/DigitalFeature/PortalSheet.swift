// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import DesignSystem
import SwiftUI

struct PortalSheet: View {
    let session: PortalSession
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var handedOffToApp = false

    private var appName: String { session.offer.app?.name ?? .local("l'app") }

    var body: some View {
        NavigationStack {
            PortalWebView(url: session.url, cookies: session.cookies, isLoading: $isLoading, handedOffToApp: $handedOffToApp)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if handedOffToApp {
                        VStack(spacing: 14) {
                            Image(systemName: "arrow.up.forward.app").font(.largeTitle).foregroundStyle(Color.brandViolet)
                            Text(.local("Ouvert dans \(appName)")).font(.title3.weight(.bold))
                            Button(.local("Fermer")) { dismiss() }.buttonStyle(.prominent(size: .large))
                        }
                        .padding(28)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }
                .navigationTitle(session.offer.provider)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(.local("Fermer")) { dismiss() } }
                    if isLoading { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
                }
        }
    }
}
#endif
