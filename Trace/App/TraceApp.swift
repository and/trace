import SwiftUI
import SwiftData
import UserNotifications

@main
struct TraceApp: App {
    /// Built here rather than left to the scene modifier, so the notification
    /// delegate can reach the same store when a tap arrives with the app closed.
    /// One container, shared — two over the same store would be two writers.
    private let container: ModelContainer?
    private let delegate: NotificationDelegate

    init() {
        let container = try? ModelContainer(for: Activity.self)
        self.container = container
        self.delegate = NotificationDelegate(container: container)
        UNUserNotificationCenter.current().delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container)
            } else {
                Text("Could not open the activity store.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var existing: [Activity]

    // One store shared by both tabs, so authorisation is requested once and
    // the daily series isn't fetched twice.
    @StateObject private var health = HealthStore()

    /// Which tab opens first. DEBUG-only `-start-tab` sets it so screenshots
    /// of Trends need no UI driving; it seeds state rather than pinning it —
    /// a constant binding here would leave the tab bar inert.
    private static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-start-tab"), i + 1 < args.count {
            return args[i + 1].lowercased() == "trends" ? 1 : 0
        }
        #endif
        return 0
    }

    @State private var selectedTab = RootView.initialTab

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(health: health)
                .tabItem { Label("Today", systemImage: "waveform.path.ecg") }
                .tag(0)
            TrendView(health: health)
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
                .tag(1)
        }
        .task {
            // Ask on launch rather than behind a button: the app is useless
            // without it, and HealthKit only ever shows the sheet once. Under
            // UI test the request is skipped so no system sheet can block the
            // run — the views being exercised do not need health data.
            #if DEBUG
            prepareDebugData()
            #endif
            #if DEBUG
            // Sample data still loads under UI test: it bypasses HealthKit, so
            // there is no permission sheet to avoid and the Trends screen needs
            // something to draw.
            if SampleData.isEnabled {
                await health.load()
                return
            }
            #endif
            guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else { return }
            if !health.didRequestAuth { await health.requestAuthorization() }
        }
    }

    #if DEBUG
    /// Resets and seeds in one pass. These cannot be separate steps that both
    /// consult `existing`: the @Query still reports the pre-delete contents
    /// within the same update, so a seeder checking it after a reset decides
    /// the store is occupied and silently skips.
    private func prepareDebugData() {
        let shouldReset = ProcessInfo.processInfo.arguments.contains("-reset-data")
        if shouldReset {
            for activity in existing { context.delete(activity) }
        }

        guard SampleData.isEnabled else { return }
        guard shouldReset || existing.isEmpty else { return }

        for (label, start, end) in SampleData.activities() {
            context.insert(Activity(label: label, start: start, end: end))
        }
    }
    #endif
}
