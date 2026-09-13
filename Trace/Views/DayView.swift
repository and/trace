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

    /// Where the scrollable x axis is parked. It must be re-anchored whenever
    /// the day changes, or it keeps pointing into the previous day's domain and
    /// the chart renders empty.
    @State private var scrollPosition: Date = Calendar.current.startOfDay(for: .now)

    /// Hoisted out of the chart builder: inferring `.init(x:y:)` and the
    /// leaf strategies in place exceeds the type checker's budget.
    private static let labelOverflow = AnnotationOverflowResolution(
        x: AnnotationOverflowResolution.Strategy.fit(to: .plot),
        y: AnnotationOverflowResolution.Strategy.disabled
    )

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

    private var dayEnd: Date { DayCursor.bounds(of: day).upperBound }

    /// The most recent moment with data on this day. Zooming lands here rather
    /// than at midnight — the end of a day is the part you just lived through,
    /// and on a past day the hours after the last reading are empty anyway.
    private var dataEnd: Date { samples.last?.date ?? dayEnd }

    /// Activities clipped to this day, so a session crossing midnight shows
    /// only the part that belongs here.
    private var bands: [Band] {
        let spans: [(id: PersistentIdentifier, span: BandSpan)] = activities.compactMap { activity in
            guard let span = BandLayout.clip(
                label: activity.label,
                start: activity.start,
                end: activity.end,
                toDayStarting: day
            ) else { return nil }
            return (id: activity.persistentModelID, span: span)
        }
        return spans
            .sorted { $0.span.start < $1.span.start }
            .enumerated()
            .map { Band(id: $0.element.id, span: $0.element.span, row: $0.offset % 2) }
    }

    private struct Band: Identifiable {
        let id: PersistentIdentifier
        let span: BandSpan
        /// Alternating label row. Bands often sit close together, and labels
        /// wider than their band would otherwise overlap each other.
        let row: Int
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
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier("day.previous")
            Spacer()
            VStack {
                Text(day.formatted(.dateTime.day().month(.wide).year()))
                    .font(.headline)
                    .accessibilityIdentifier("day.label")
                Text("HEART RATE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next day")
            .accessibilityIdentifier("day.next")
            .disabled(DayCursor.isAtPresent(day: day))
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
                    withAnimation(.easeOut(duration: 0.2)) { setSpan(Self.maxSpan) }
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
                    xStart: .value("Start", band.span.start),
                    xEnd: .value("End", band.span.end),
                    yStart: .value("BPM", yDomain.lowerBound),
                    yEnd: .value("BPM", yDomain.upperBound)
                )
                .foregroundStyle(Color.seriesPrimary.opacity(0.14))
                // Fitting to the plot keeps the label inside it, so a narrow
                // band near an edge no longer pushes its label over the axis
                // labels. Without it the label is centred on the band and a
                // short activity's name spills straight out of the chart.
                .annotation(
                    position: .overlay,
                    alignment: .top,
                    spacing: 4,
                    overflowResolution: Self.labelOverflow
                ) {
                    BandLabel(text: band.span.label, row: band.row)
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
        .chartScrollPosition(x: $scrollPosition)
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        handleDoubleTap(at: location, proxy: proxy, geometry: geometry)
                    }
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

    /// Zooming where the finger landed, rather than at some fixed point:
    /// a double tap inside an activity frames that activity, one on open chart
    /// centres on that moment, and a second tap zooms back out.
    private func handleDoubleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !isZoomed else {
            withAnimation(.easeOut(duration: 0.2)) { setSpan(Self.maxSpan) }
            return
        }
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let instant: Date = proxy.value(atX: x) else { return }
        withAnimation(.easeOut(duration: 0.2)) { zoom(around: instant) }
    }

    private func zoom(around instant: Date) {
        if let band = bands.first(where: { $0.span.start <= instant && instant <= $0.span.end }) {
            // Frame the activity with a margin, so you see its edges in context
            // rather than flush against them.
            let margin = max(300, band.span.duration * 0.3)
            let span = min(Self.maxSpan, max(Self.minSpan, band.span.duration + margin * 2))
            visibleSpan = span
            scrollPosition = DayCursor.anchor(
                span: span, endingAt: band.span.end.addingTimeInterval(margin), in: day)
        } else {
            let span = 3 * 3600.0
            visibleSpan = span
            scrollPosition = DayCursor.anchor(
                span: span, endingAt: instant.addingTimeInterval(span / 2), in: day)
        }
    }

    /// Changes the window and re-anchors it in one move. Setting a span
    /// without moving the scroll position leaves the chart parked wherever it
    /// was — which is how a zoom ended up showing midnight.
    private func setSpan(_ span: TimeInterval) {
        visibleSpan = span
        scrollPosition = span >= Self.maxSpan
            ? day
            : DayCursor.anchor(span: span, endingAt: dataEnd, in: day)
    }

    private func shift(_ days: Int) {
        guard let next = DayCursor.step(from: day, by: days) else { return }
        day = next
        // The zoom level is kept — losing it on every step made comparing the
        // same hour across days tedious. The anchor must still be recomputed
        // for the new day, or the scroll offset points outside its domain and
        // the chart renders blank. reload() re-anchors once samples arrive.
        scrollPosition = visibleSpan >= Self.maxSpan
            ? next
            : DayCursor.anchor(span: visibleSpan, endingAt: DayCursor.bounds(of: next).upperBound, in: next)
    }

    private func reload() async {
        loading = true
        samples = await health.heartRate(on: day)
        loading = false

        // Now that the day's readings are known, park a retained zoom over the
        // part of the day that actually has data.
        if visibleSpan < Self.maxSpan {
            scrollPosition = DayCursor.anchor(span: visibleSpan, endingAt: dataEnd, in: day)
        }
    }
}

/// The chip naming an activity band. Kept as its own view: inlined in the
/// chart builder, its modifier chain blows the type checker's budget.
private struct BandLabel: View {
    let text: String
    let row: Int

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(Color.seriesPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background)
            .fixedSize()
            .offset(y: CGFloat(row) * 15)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.background.opacity(0.75))
    }
}
