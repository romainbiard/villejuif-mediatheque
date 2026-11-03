// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BackgroundTasks
import MediathequeCore
import SwiftUI

@main
struct MediathequeApp: App {
    @State private var session = SessionStore()
    @State private var showsSplash = true
    @Environment(\.scenePhase) private var scenePhase

    /// Matches `BGTaskSchedulerPermittedIdentifiers` in project.yml: the bundle identifier + ".refresh".
    nonisolated static let refreshTaskID = (Bundle.main.bundleIdentifier ?? "mediatheques-villejuif") + ".refresh"

    init() {
        #if DEBUG
        UITesting.configureIfNeeded()
        #endif
        // Covers and posters (AsyncImage goes through URLSession.shared): the default cache,
        // a few MB, empties as soon as you scroll through a search. This way images persist from one launch to the next.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .overlay {
                    if showsSplash { SplashOverlay(isPresented: $showsSplash) }
                }
                .environment(session)
                .task { await session.restore() }
        }
        .commands { AppCommands() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Self.scheduleRefresh()
                session.didEnterBackground()
            case .active:
                Task { await session.didBecomeActive() }
            default:
                break
            }
        }
        // Background wake-up: snapshot for the widget, reminders, holds that have arrived.
        // `SessionManager` restores the session from the keychain when needed.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            Self.scheduleRefresh()
            _ = try? await AccountSync.run(settings: .current())
        }
    }

    /// One request roughly every 6 hours; iOS picks the actual time.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
