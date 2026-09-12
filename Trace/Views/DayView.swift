import SwiftUI
import SwiftData
import Charts

/// One day of heart rate with each logged activity drawn as a band spanning
/// its real duration — the intraday view, where a 90-minute session is
/// actually visible.
struct DayView: View {
    @ObservedObject var health: HealthStore
    @Query(sort: \Activity.start) private var activities: [Activity]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var samples: [HRSample] = []
    @State private var loading = false

    /// Width of the visible time window, in seconds. The whole day by default;
    /// pinch narrows it and Charts handles the panning natively, so this never
    /// competes with the enclosing List's vertical scroll.
    @State private var visibleSpan: TimeInterval = 86_400
    @State private var spanAtPinchStart: TimeInterval?

    private static let minSpan: TimeInterval = 900      // 15 minutes
    private static let maxSpan: TimeInterval = 86_400   // the full day

    private var isZoomed: Bool { visibleSpan < Self.maxSpan - 1 }

    /// Explicit y range, with headroom above the trace for the band labels to
    /// occupy. Labels sit INSIDE the plot area: a scrollable chart clips
    /// anything drawn outside it.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.bpm)
        guard let lo = values.min(), let hi = values.max() else { return 40...140 }
        let floor = max(30, lo - 8)
        return floor...(hi + max(18, (hi - floor) * 0.22))
    }

    /// Tick spacing that stays legible as the window narrows.
    private var tickHours: Int {
        switch visibleSpan {
        case ..<7_200:   return 1
        case ..<21_600:  return 2
        case ..<43_200:  return 3
        default:         return 6
        }
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
    }

    /// Activities clipped to this day, so a session crossing midnight shows
    /// only the part that belongs here.
    private var bands: [Band] {
        activities.compactMap { activity in
            let start = max(activity.start, day)
            let end = min(activity.end ?? .now, dayEnd)
            guard end > start else { return nil }
            return Band(id: activity.persistentModelID, label: activity.label, start: start, end: end)
        }
        .sorted { $0.start < $1.start }
    }

    private struct Band: Identifiable {
        let id: PersistentIdentifier
        let label: String
        let start: Date
        let end: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if loading {
                ProgressView().frame(height: 240)
            } else if samples.isEmpty {
                Text("No heart-rate data for this day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 240, alignment: .center)
            } else {
                chart
                zoomBar
                caption
            }
        }
        .task(id: day) { await reload() }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack {
                Text(day.formatted(.dateTime.day().month(.wide).year()))
                    .font(.headline)
                Text("HEART RATE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(dayEnd > Date())
        }
    }

    private var zoomBar: some View {
        HStack {
            Text(isZoomed ? "\(Int(visibleSpan / 3600))h window — pinch to zoom, drag to pan"
                          : "Pinch the chart to zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if isZoomed {
                Button("Full day") {
                    withAnimation(.easeOut(duration: 0.2)) { visibleSpan = Self.maxSpan }
                }
                .font(.caption2)
            }
        }
    }

    private var chart: some View {
        Chart {
            // Bands first so the line draws over them.
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Start", band.start),
                    xEnd: .value("End", band.end),
                    yStart: .value("BPM", yDomain.lowerBound),
                    yEnd: .value("BPM", yDomain.upperBound)
                )
                .foregroundStyle(Color.seriesPrimary.opacity(0.14))
                .annotation(position: .overlay, alignment: .top, spacing: 4) {
                    Text(band.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.seriesPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.background.opacity(0.75))
                        )
                        .fixedSize()
                }
            }

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("BPM", sample.bpm)
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Color.seriesPrimary)
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: day...dayEnd)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: tickHours)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleSpan)
        .frame(height: 240)
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = spanAtPinchStart ?? visibleSpan
                    if spanAtPinchStart == nil { spanAtPinchStart = base }
                    visibleSpan = min(Self.maxSpan,
                                      max(Self.minSpan, base / value.magnification))
                }
                .onEnded { _ in spanAtPinchStart = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                visibleSpan = isZoomed ? Self.maxSpan : 3 * 3600
            }
        }
    }

    private var caption: some View {
        Text(bands.isEmpty
             ? "\(samples.count) readings. Log an activity and it will appear as a band here."
             : "\(samples.count) readings. Shaded bands span each logged activity.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func shift(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        day = next
    }

    private func reload() async {
        loading = true
        samples = await health.heartRate(on: day)
        loading = false
    }
}
