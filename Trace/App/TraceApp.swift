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
    @Environment(\.modelContext) private var context
    @Query private var existing: [Activity]

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
            #if DEBUG
            seedSampleActivitiesIfNeeded()
            #endif
            guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else { return }
            if !health.didRequestAuth { await health.requestAuthorization() }
        }
    }

    #if DEBUG
    /// Inserts the screenshot activities once, only under `-sample-data`.
    private func seedSampleActivitiesIfNeeded() {
        guard SampleData.isEnabled, existing.isEmpty else { return }
        for (label, start, end) in SampleData.activities() {
            context.insert(Activity(label: label, start: start, end: end))
        }
    }
    #endif
}
