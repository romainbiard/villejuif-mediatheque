// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import MediathequeCore
import SwiftUI

/// Takes over from the system launch screen (same magenta, same crest in the same spot),
/// then fades into the app: the crest grows as it disappears, like a door opening.
/// It leaves as soon as the session is restored, never holding the app longer than `maximumDuration`.
struct SplashOverlay: View {
    @Binding var isPresented: Bool
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLeaving = false

    /// Width of the crest on the launch screen (size of the `LaunchCrest` PDF).
    static let crestWidth: CGFloat = 120
    /// Avoids a mere flicker when the session is already ready.
    static let minimumDuration: Duration = .milliseconds(350)
    /// Beyond this, the app takes over with its own loading states.
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
