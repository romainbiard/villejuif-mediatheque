import BackgroundTasks
import MediathequeCore
import SwiftUI

@main
struct VillejuifApp: App {
    @State private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    nonisolated static let refreshTaskID = "com.rbiard.mediatheques-villejuif.refresh"

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(session)
                .task { await session.restore() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
        // Réveil en tâche de fond : snapshot pour le widget, rappels, réservations arrivées.
        // La session est rouverte au besoin avec le trousseau par `SessionManager`.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            Self.scheduleRefresh()
            _ = try? await AccountSync.run(settings: .current())
        }
    }

    /// Une demande toutes les 6 heures environ ; iOS choisit le moment réel.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
