import SwiftData
import SwiftUI

@main
struct AudayApp: App {
    init() {
        PhoneConnectivity.shared.activate()
        BackgroundProcessing.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            DayTimelineView()
                .tabItem { Label("Timeline", systemImage: "waveform") }
            ChatView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.pink)
        .preferredColorScheme(settings.colorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasOnboarded },
            set: { settings.hasOnboarded = !$0 }
        )) {
            OnboardingView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                ProcessingQueue.shared.enqueue()
                PhoneConnectivity.shared.pushStatus()
            case .background:
                BackgroundProcessing.schedule()
            default:
                break
            }
        }
    }
}
