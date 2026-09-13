import Foundation
import HealthKit

@MainActor
final class HealthStore: ObservableObject {

    /// Typical heart rate per hour of day, built from recent history. Used to
    /// say whether an activity ran hot for the time of day it happened at.
    @Published private(set) var hourlyBaseline: [Int: Double] = [:]

    /// Bumped on every explicit refresh. Views key their load task on it, so a
    /// pull-to-refresh or a return to the foreground re-reads HealthKit — the
    /// chart otherwise only ever loaded on appear and went stale in place.
    @Published private(set) var refreshToken = 0
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

    /// Re-reads everything. Watch samples arrive on the phone in batches, so
    /// data logged minutes ago may only appear after a refresh.
    func refresh() async {
        refreshToken += 1
        await load()
    }

    /// Builds the typical-heart-rate-per-hour baseline. That is all this does
    /// now: the daily strain series it used to compute lost its graph, and
    /// recomputing it on every refresh was work nothing read.
    func load(daysBack: Int = 30) async {
        #if DEBUG
        if SampleData.isEnabled {
            hourlyBaseline = SampleData.hourlyBaseline()
            return
        }
        #endif
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        hourlyBaseline = await buildHourlyBaseline(daysBack: daysBack)
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
        return await heartRate(from: start, to: end)
    }

    /// Raw samples in an arbitrary window — used for one activity's span.
    func heartRate(from start: Date, to end: Date) async -> [HRSample] {
        #if DEBUG
        if SampleData.isEnabled {
            return SampleData.heartRate(on: start).filter { $0.date >= start && $0.date <= end }
        }
        #endif
        guard isAvailable else { return [] }

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

    /// Hourly averages over recent history, collapsed into one typical value
    /// per hour of day. A statistics query does the bucketing in HealthKit
    /// rather than pulling tens of thousands of raw samples across.
    private func buildHourlyBaseline(daysBack: Int) async -> [Int: Double] {
        #if DEBUG
        if SampleData.isEnabled { return SampleData.hourlyBaseline() }
        #endif
        guard isAvailable else { return [:] }

        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: end) else { return [:] }

        let averages: [(date: Date, bpm: Double)] = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: hrType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .discreteAverage,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var out: [(date: Date, bpm: Double)] = []
                let unit = HKUnit.count().unitDivided(by: .minute())
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let value = stat.averageQuantity()?.doubleValue(for: unit) {
                        out.append((date: stat.startDate, bpm: value))
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }

        return LoadCalculator.hourlyBaseline(hourlyAverages: averages)
    }
}
