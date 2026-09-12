import SwiftUI
import SwiftData
import Charts

struct TrendView: View {
    @ObservedObject var health: HealthStore
    @Query(sort: \Activity.start) private var activities: [Activity]

    @State private var selectedLabel: String?

    private var labels: [String] {
        Array(Set(activities.map(\.label))).sorted()
    }

    /// Days on which the selected label was logged, for the overlay marks.
    private var selectedDays: Set<Date> {
        guard let selectedLabel else { return [] }
        return Set(activities.filter { $0.label == selectedLabel }.flatMap { $0.days() })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if health.days.allSatisfy({ $0.stress == nil }) {
                        emptyState
                    } else {
                        stressChart
                        if !labels.isEmpty { comparisonChart }
                    }
                }
                .padding()
            }
            .navigationTitle("Trends")
            .task { await health.load() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No health data yet").font(.headline)
            Text("Trace needs several days of HRV and resting heart rate before a baseline means anything. Wear your watch overnight and check back.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Daily strain, with activity days marked underneath

    private var stressChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily strain").font(.headline)
            Text("50 is a typical day for you. Higher means lower HRV or a raised resting heart rate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(health.days.filter { $0.stress != nil }) { day in
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Strain", day.stress ?? 0)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.seriesPrimary)
                }

                RuleMark(y: .value("Baseline", 50))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.4))

                // Activity days are marked as presence on the same axis, not a
                // second scale — a dual-axis chart would invite a causal read
                // the data cannot support.
                ForEach(health.days.filter { selectedDays.contains($0.date) }) { day in
                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Strain", day.stress ?? 0)
                    )
                    .symbolSize(80)
                    .foregroundStyle(Color.seriesPrimary)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 220)

            if !labels.isEmpty {
                Picker("Highlight", selection: $selectedLabel) {
                    Text("None").tag(String?.none)
                    ForEach(labels, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Mean strain on days with each activity

    private var comparisonChart: some View {
        let overall = mean(health.days.compactMap(\.stress))

        return VStack(alignment: .leading, spacing: 8) {
            Text("Strain by activity").font(.headline)
            Text("Mean strain on days each activity was logged, against your \(overall.map { String(format: "%.0f", $0) } ?? "—") average.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(labelSummaries(), id: \.label) { row in
                BarMark(
                    x: .value("Strain", row.mean),
                    y: .value("Activity", row.label)
                )
                .cornerRadius(4)
                .foregroundStyle(Color.seriesPrimary)
                .annotation(position: .trailing) {
                    Text(String(format: "%.0f", row.mean))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...100)
            .frame(height: CGFloat(labelSummaries().count) * 44 + 20)

            Text("Days logged, not proof of cause — a heavy study day and a bad night's sleep tend to arrive together.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private struct LabelSummary { let label: String; let mean: Double; let days: Int }

    private func labelSummaries() -> [LabelSummary] {
        let stressByDay = Dictionary(
            uniqueKeysWithValues: health.days.compactMap { day in
                day.stress.map { (day.date, $0) }
            }
        )

        return labels.compactMap { label in
            let days = Set(activities.filter { $0.label == label }.flatMap { $0.days() })
            let values = days.compactMap { stressByDay[$0] }
            guard let m = mean(values) else { return nil }
            return LabelSummary(label: label, mean: m, days: values.count)
        }
        .sorted { $0.mean > $1.mean }
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

extension Color {
    /// Validated categorical slot 1 — steps chosen per mode for contrast.
    static let seriesPrimary = Color(
        light: Color(red: 0x2a / 255, green: 0x78 / 255, blue: 0xd6 / 255),
        dark:  Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xe5 / 255)
    )

    init(light: Color, dark: Color) {
        self = Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
