import MediathequeCore
import SwiftUI

/// Prend le relais de l'écran de lancement système (même magenta, même blason au même endroit),
/// puis s'efface vers l'app : le blason grandit en disparaissant, comme une porte qui s'ouvre.
/// Il part dès que la session est rouverte, sans jamais retenir l'app plus de `maximumDuration`.
struct SplashOverlay: View {
    @Binding var isPresented: Bool
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLeaving = false

    /// Largeur du blason dans l'écran de lancement (taille du PDF `LaunchCrest`).
    static let crestWidth: CGFloat = 120
    /// Évite un simple clignotement quand la session est déjà prête.
    static let minimumDuration: Duration = .milliseconds(350)
    /// Au-delà, l'app prend le relais avec ses propres états de chargement.
    static let maximumDuration: Duration = .milliseconds(1500)

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .opacity(isLeaving ? 0 : 1)
            Image("LaunchCrest")
                .resizable()
                .scaledToFit()
                .frame(width: Self.crestWidth)
                .scaleEffect(isLeaving && !reduceMotion ? 1.8 : 1)
                .opacity(isLeaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!isLeaving)
        .accessibilityHidden(true)
        .task { await leaveWhenReady() }
    }

    private func leaveWhenReady() async {
        let clock = ContinuousClock()
        let start = clock.now
        try? await Task.sleep(for: Self.minimumDuration)
        while session.state == .restoring, clock.now - start < Self.maximumDuration {
            try? await Task.sleep(for: .milliseconds(50))
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .smooth(duration: 0.5)) {
            isLeaving = true
        } completion: {
            isPresented = false
        }
    }
}

#Preview {
    SplashOverlay(isPresented: .constant(true))
        .environment(SessionStore())
}
