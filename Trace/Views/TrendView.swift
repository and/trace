import SwiftUI
import SwiftData
import Charts

/// What your heart did during each logged activity.
///
/// This replaces a daily strain score. That score was built from resting heart
/// rate and HRV — both measured at or near rest — so it described the night
/// rather than the day, and could not tell two activities on the same date
/// apart. Everything here is measured inside the activity's own window.
struct TrendView: View {
    @ObservedObject var health: HealthStore
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    @State private var loads: [ActivityLoad] = []
    @State private var loading = false

    /// Hoisted out of the chart builder: inferring this in place costs the type
    /// checker more than it can spend.
    private static let annotationOverflow = AnnotationOverflowResolution(
        x: AnnotationOverflowResolution.Strategy.fit(to: .chart),
        y: AnnotationOverflowResolution.Strategy.disabled
    )

    /// Only finished activities, and only recent ones — older sessions are
    /// beyond the window the baseline is built from.
    private var finished: [Activity] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return activities.filter { $0.end != nil && $0.start >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    } else if loads.isEmpty {
                        emptyState
                    } else {
                        comparison
                        detail
                    }
                }
                .padding()
            }
            .navigationTitle("Activity")
            .task(id: RefreshKey(count: finished.count, token: health.refreshToken)) {
                await reload()
            }
        }
    }

    private struct RefreshKey: Equatable {
        let count: Int
        let token: Int
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to compare yet").font(.headline)
            Text(finished.isEmpty
                 ? "Log an activity and this will show what your heart rate did during it."
                 : "No heart-rate readings landed inside your logged activities. The watch samples every few minutes, so very short sessions can miss it entirely.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mean heart rate per activity

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart rate by activity").font(.headline)
            Text("Average beats per minute measured during each session, against your usual rate for that time of day.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(byLabel(), id: \.label) { row in
                BarMark(
                    x: .value("BPM", row.meanBPM),
                    y: .value("Activity", row.label)
                )
                .cornerRadius(4)
                .foregroundStyle(Color.seriesPrimary.opacity(row.isReliable ? 1 : 0.35))
                .annotation(position: .trailing, overflowResolution: Self.annotationOverflow) {
                    BarValue(mean: row.meanBPM, delta: row.delta)
                }
            }
            .chartXScale(domain: 40...(maxBPM + 10))
            .frame(height: CGFloat(byLabel().count) * 44 + 20)

            Text("A positive figure means your heart ran that many beats above your usual for the hours involved. Faded bars rest on fewer than five readings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Individual sessions

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions").font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(loads.enumerated()), id: \.offset) { index, load in
                    if index > 0 { Divider() }
                    sessionRow(load)
                }
            }
        }
    }

    private func sessionRow(_ load: ActivityLoad) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(load.label)
                Text(load.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    if let delta = load.delta {
                        let rounded = Int(delta.rounded())
                        Text(deltaText(delta))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(rounded > 0 ? Color.seriesWarm
                                             : rounded < 0 ? Color.seriesPrimary : Color.secondary)
                    }
                    Text("\(Int(load.meanBPM.rounded())) bpm")
                        .font(.body.monospacedDigit())
                }
                Text("peak \(Int(load.peakBPM.rounded())) · \(load.sampleCount) readings")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private var maxBPM: Double {
        max(100, loads.map(\.meanBPM).max() ?? 100)
    }

    private func deltaText(_ delta: Double) -> String {
        let rounded = Int(delta.rounded())
        return rounded >= 0 ? "+\(rounded)" : "\(rounded)"
    }

    /// One row per label, pooling every session that carried it.
    private func byLabel() -> [ActivityLoad] {
        Dictionary(grouping: loads, by: \.label).map { label, group in
            let samples = group.reduce(0) { $0 + $1.sampleCount }
            let weightedMean = group.reduce(0.0) { $0 + $1.meanBPM * Double($1.sampleCount) } / Double(samples)
            let baselines = group.compactMap(\.baselineBPM)
            return ActivityLoad(
                label: label,
                start: group.map(\.start).min() ?? .now,
                end: group.map(\.end).max() ?? .now,
                sampleCount: samples,
                meanBPM: weightedMean,
                peakBPM: group.map(\.peakBPM).max() ?? 0,
                baselineBPM: baselines.isEmpty
                    ? nil
                    : baselines.reduce(0, +) / Double(baselines.count)
            )
        }
        .sorted { $0.meanBPM > $1.meanBPM }
    }

    private func reload() async {
        loading = true
        defer { loading = false }

        if health.hourlyBaseline.isEmpty { await health.load() }

        var built: [ActivityLoad] = []
        for activity in finished {
            guard let end = activity.end else { continue }
            let samples = await health.heartRate(from: activity.start, to: end)
            if let load = LoadCalculator.load(
                label: activity.label,
                start: activity.start,
                end: end,
                samples: samples,
                hourly: health.hourlyBaseline
            ) {
                built.append(load)
            }
        }
        loads = built
    }
}

/// The figure beside a bar. Its own view so the chart builder is not solving a
/// modifier chain inside an annotation closure.
private struct BarValue: View {
    let mean: Double
    let delta: Double?

    var body: some View {
        HStack(spacing: 5) {
            Text("\(Int(mean.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let delta {
                let rounded = Int(delta.rounded())
                Text(rounded > 0 ? "+\(rounded)" : "\(rounded)")
                    .font(.caption2.monospacedDigit())
                    // Zero is not "elevated": colour it like any other neutral
                    // figure rather than flagging it.
                    .foregroundStyle(deltaColor(rounded))
            }
        }
        .fixedSize()
    }

    private func deltaColor(_ rounded: Int) -> Color {
        if rounded > 0 { return .seriesWarm }
        if rounded < 0 { return .seriesPrimary }
        return .secondary
    }
}

extension Color {
    /// Validated categorical slot 1 — steps chosen per mode for contrast.
    static let seriesPrimary = Color(
        light: Color(red: 0x2a / 255, green: 0x78 / 255, blue: 0xd6 / 255),
        dark:  Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xe5 / 255)
    )

    /// Slot 2, for a figure that reads as "above usual" beside the blue.
    static let seriesWarm = Color(
        light: Color(red: 0xeb / 255, green: 0x68 / 255, blue: 0x34 / 255),
        dark:  Color(red: 0xd9 / 255, green: 0x59 / 255, blue: 0x26 / 255)
    )

    init(light: Color, dark: Color) {
        self = Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
