import HealthKit
import SwiftUI
import WatchKit

/// Receives the workout configuration sent by `HKHealthStore.startWatchApp(with:)` on the iPhone,
/// which launches this app in the background so it can start recording remotely.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchRecorder.shared.start() }
    }
}

@main
struct AudayWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

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
