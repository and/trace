import Foundation
import HealthKit

@MainActor
final class HealthStore: ObservableObject {

    @Published private(set) var days: [DayMetrics] = []
    @Published private(set) var didRequestAuth = false
    @Published private(set) var isLoading = false

    private let store = HKHealthStore()

    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let rhrType = HKQuantityType(.restingHeartRate)
    private let hrType = HKQuantityType(.heartRate)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit never reveals whether READ access was granted — a denied type
    /// simply returns no samples, which is indistinguishable from having no
    /// data. So this only records that we asked; it never branches on the answer.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [hrvType, rhrType, hrType]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch {
            // Nothing actionable: queries below will just come back empty.
        }
        didRequestAuth = true
        await load()
    }

    func load(daysBack: Int = 60) async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: end) else { return }

        async let hrv = dailyAverage(hrvType, unit: .secondUnit(with: .milli), from: start, to: end)
        async let rhr = dailyAverage(rhrType, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end)

        let (hrvByDay, rhrByDay) = await (hrv, rhr)

        var out: [DayMetrics] = []
        var day = start
        while day <= end {
            out.append(DayMetrics(date: day, hrv: hrvByDay[day], restingHR: rhrByDay[day]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        days = StressScore.annotate(out)
    }

    /// Daily means via HKStatisticsCollectionQuery — one bucketed query rather
    /// than pulling every raw sample and aggregating on our side.
    private func dailyAverage(
        _ type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> [Date: Double] {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .discreteAverage,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let value = stat.averageQuantity()?.doubleValue(for: unit) {
                        out[Calendar.current.startOfDay(for: stat.startDate)] = value
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Raw heart-rate samples for one day, for the intraday chart. Outside a
    /// workout the watch samples every few minutes, so expect a sparse line
    /// rather than a smooth trace.
    func heartRate(on day: Date) async -> [HRSample] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let out = (samples as? [HKQuantitySample] ?? []).map {
                    HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }
}
