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
        x: AnnotationOverflowResolution.Strategy.fit(to: .plot),
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
        let rows = comparable()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Heart rate by activity").font(.headline)
            Text("How far each activity ran from your usual rate for the hours it covered.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(rows, id: \.label) { row in
                // Bars run from zero — your own baseline — so length encodes the
                // deviation honestly. Drawing absolute bpm from a 40 floor made
                // 92 and 108 look three times apart.
                BarMark(
                    xStart: .value("Usual", 0),
                    xEnd: .value("Difference", row.delta ?? 0),
                    // The row header carries the absolute rate: there is space
                    // there, and past the bar there is not — a "92 bpm +10"
                    // annotation had to be shoved back over its own bar.
                    y: .value("Activity", "\(row.label)  ·  \(Int(row.meanBPM.rounded())) bpm")
                )
                .cornerRadius(3)
                .foregroundStyle((row.delta ?? 0) >= 0 ? Color.seriesWarm : Color.seriesPrimary)
                .opacity(row.isReliable ? 1 : 0.35)
                .annotation(
                    position: Int((row.delta ?? 0).rounded()) < 0 ? .leading : .trailing,
                    spacing: 6,
                    overflowResolution: Self.annotationOverflow
                ) {
                    DeltaLabel(delta: row.delta ?? 0)
                }

                RuleMark(x: .value("Usual", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .chartXScale(domain: -deltaExtent...deltaExtent)
            .chartXAxis(.hidden)
            .frame(height: CGFloat(rows.count) * 44 + 8)

            Text(caption(for: rows))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The zero line is your usual rate, so the axis is symmetric around it —
    /// an asymmetric one would make a small rise look larger than an equal fall.
    private var deltaExtent: Double {
        let largest = comparable().compactMap { $0.delta.map(abs) }.max() ?? 5
        return max(6, largest * 1.45)
    }

    private func caption(for rows: [ActivityLoad]) -> String {
        let base = "Bars run from your usual rate for those hours: right is faster, left is slower, and the figure beside each bar is the difference in beats per minute."
        let unreliable = rows.contains { !$0.isReliable }
        let unmeasured = byLabel().count - rows.count
        var parts = [base]
        if unreliable { parts.append("Faded bars rest on fewer than five readings.") }
        if unmeasured > 0 {
            parts.append("\(unmeasured) activity\(unmeasured == 1 ? "" : "s") had too little history for those hours to compare against.")
        }
        return parts.joined(separator: " ")
    }

    /// Only labels with a baseline can be placed against it.
    private func comparable() -> [ActivityLoad] {
        byLabel().filter { $0.delta != nil }.sorted { ($0.delta ?? 0) > ($1.delta ?? 0) }
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

/// The signed difference beside a bar. Kept short deliberately — anything
/// longer cannot fit past a bar that already reaches most of the plot. Its own
/// view so the chart builder is not solving a modifier chain in a closure.
private struct DeltaLabel: View {
    let delta: Double

    var body: some View {
        let rounded = Int(delta.rounded())
        Text(rounded > 0 ? "+\(rounded)" : "\(rounded)")
            .font(.caption.monospacedDigit())
            // Zero is not "elevated": colour it neutrally rather than flag it.
            .foregroundStyle(rounded > 0 ? Color.seriesWarm
                             : rounded < 0 ? Color.seriesPrimary : Color.secondary)
            .fixedSize()
    }
}

extension Color {
    /// Validated categorical slot 1 — steps chosen per mode for contrast.
    static let seriesPrimary = Color(
        light: Color(red: 0x2a / 255, green: 0x78 / 255, blue: 0xd6 / 255),
        dark:  Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xe5 / 255)
    )

    /// The warm pole of the diverging pair. This chart runs either side of
    /// your usual rate, so it needs two colours that read as opposites with a
    /// neutral middle — blue and red, not two neighbouring categorical hues.
    static let seriesWarm = Color(
        light: Color(red: 0xe3 / 255, green: 0x49 / 255, blue: 0x48 / 255),
        dark:  Color(red: 0xe6 / 255, green: 0x67 / 255, blue: 0x67 / 255)
    )

    init(light: Color, dark: Color) {
        self = Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
