import SwiftUI
import SwiftData

@main
struct TraceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Activity.self)
    }
}

struct RootView: View {
    // One store shared by both tabs, so authorisation is requested once and
    // the daily series isn't fetched twice.
    @StateObject private var health = HealthStore()

    var body: some View {
        TabView {
            HomeView(health: health)
                .tabItem { Label("Today", systemImage: "waveform.path.ecg") }
            TrendView(health: health)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
        }
        .task {
            // Ask on launch rather than behind a button: the app is useless
            // without it, and HealthKit only ever shows the sheet once. Under
            // UI test the request is skipped so no system sheet can block the
            // run — the views being exercised do not need health data.
            guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else { return }
            if !health.didRequestAuth { await health.requestAuthorization() }
        }
    }
}
