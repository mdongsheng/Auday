import SwiftUI

@main
struct AudayWatchApp: App {
    init() {
        WatchLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                RecordView()
                AskView()
                RecentView()
            }
            .tabViewStyle(.verticalPage)
            .onOpenURL { url in
                // Complication tap: auday://record
                if url.host == "record" {
                    Task { await WatchRecorder.shared.start() }
                }
            }
        }
    }
}
