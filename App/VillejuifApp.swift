import MediathequeCore
import SwiftUI

@main
struct VillejuifApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(session)
                .task { await session.restore() }
        }
    }
}
