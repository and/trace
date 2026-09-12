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
    private let mindfulType = HKCategoryType(.mindfulSession)

    /// Custom metadata key carrying the activity's label, since a mindful
    /// session has no name of its own.
    static let labelKey = "TraceActivityLabel"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit never reveals whether READ access was granted — a denied type
    /// simply returns no samples, which is indistinguishable from having no
    /// data. So this only records that we asked; it never branches on the answer.
    func requestAuthorization() async {
        #if DEBUG
        if SampleData.isEnabled {
            didRequestAuth = true
            await load()
            return
        }
        #endif
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [hrvType, rhrType, hrType]
        let share: Set<HKSampleType> = [mindfulType]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            // Nothing actionable: queries below will just come back empty.
        }
        didRequestAuth = true
        await load()
    }

    func load(daysBack: Int = 60) async {
        #if DEBUG
        if SampleData.isEnabled {
            days = SampleData.days()
            return
        }
        #endif
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
        #if DEBUG
        if SampleData.isEnabled { return SampleData.heartRate(on: day) }
        #endif
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

    // MARK: - Writing activities back to Health

    /// Saves a finished activity as a mindful session so other health apps can
    /// see it. Mindful Minutes is the only interval-shaped container in Health
    /// that is not a workout — the tradeoff is that study time and real
    /// meditation land in the same bucket.
    ///
    /// Returns the new sample's id, or nil if the write was refused. Write
    /// authorisation IS observable (unlike read), but a refusal is not worth
    /// surfacing mid-gesture — the activity is still saved locally.
    func writeActivity(label: String, start: Date, end: Date) async -> UUID? {
        guard isAvailable, end > start else { return nil }
        guard store.authorizationStatus(for: mindfulType) == .sharingAuthorized else { return nil }

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end,
            metadata: [Self.labelKey: label]
        )
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            return nil
        }
    }

    /// Removes a sample this app wrote. HealthKit only permits deleting your
    /// own samples, so this can never touch data from the Watch or another app.
    func deleteActivity(sampleID: UUID) async {
        guard isAvailable else { return }
        _ = try? await store.deleteObjects(
            of: mindfulType,
            predicate: HKQuery.predicateForObject(with: sampleID)
        )
    }

    /// Replaces the sample for an edited activity: delete then re-save, since
    /// HealthKit samples are immutable.
    func resyncActivity(previous: UUID?, label: String, start: Date, end: Date?) async -> UUID? {
        if let previous { await deleteActivity(sampleID: previous) }
        guard let end else { return nil }   // still running: nothing to write yet
        return await writeActivity(label: label, start: start, end: end)
    }
}
