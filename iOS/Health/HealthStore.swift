import Foundation
import HealthKit

struct HeartRatePoint: Identifiable {
    let date: Date
    let bpm: Double
    var id: Date { date }
}

struct HealthSnapshot {
    var averageHeartRate: Double?
    var minHeartRate: Double?
    var maxHeartRate: Double?
    var hrv: Double?
    var steps: Double?
    var activeEnergy: Double?
    var sleepHours: Double?
    var heartRateSeries: [HeartRatePoint] = []

    /// 0–100, estimated from HRV (SDNN). Lower HRV → higher estimated stress. Not a medical measure.
    var stress: Double? { hrv.map(HealthStore.stress(fromSDNN:)) }

    var promptDescription: String {
        var lines = ["Health context:"]
        if let v = averageHeartRate {
            lines.append("- Heart rate avg \(Int(v)) bpm (min \(Int(minHeartRate ?? v)), max \(Int(maxHeartRate ?? v)))")
        }
        if let v = stress { lines.append("- Estimated stress \(Int(v))/100 (from HRV \(Int(hrv ?? 0)) ms)") }
        if let v = steps { lines.append("- Steps \(Int(v))") }
        if let v = activeEnergy { lines.append("- Active energy \(Int(v)) kcal") }
        if let v = sleepHours { lines.append(String(format: "- Sleep last night %.1f h", v)) }
        if lines.count == 1 { lines.append("- No health data available") }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class HealthStore {
    static let shared = HealthStore()

    private let store = HKHealthStore()
    private let bpm = HKUnit.count().unitDivided(by: .minute())

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func stress(fromSDNN ms: Double) -> Double {
        // ~20 ms SDNN → 100 (high stress), ~100 ms → 0 (relaxed).
        min(100, max(0, (100 - ms) / 80 * 100))
    }

    private func statistic(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from start: Date,
        to end: Date
    ) async -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: options
        )
        return try? await descriptor.result(for: store)
    }

    func averageHeartRate(from start: Date, to end: Date) async -> Double? {
        await statistic(.heartRate, unit: bpm, options: .discreteAverage, from: start, to: end)?
            .averageQuantity()?.doubleValue(for: bpm)
    }

    /// HRV is sampled sparsely, so look an hour either side of the window.
    func stressEstimate(from start: Date, to end: Date) async -> Double? {
        let sdnn = await statistic(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            options: .discreteAverage,
            from: start.addingTimeInterval(-3600),
            to: end.addingTimeInterval(3600)
        )?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
        return sdnn.map(Self.stress(fromSDNN:))
    }

    func snapshot(for day: Date) async -> HealthSnapshot {
        guard isAvailable else { return HealthSnapshot() }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var snapshot = HealthSnapshot()

        let hr = await statistic(.heartRate, unit: bpm, options: [.discreteAverage, .discreteMin, .discreteMax], from: start, to: end)
        snapshot.averageHeartRate = hr?.averageQuantity()?.doubleValue(for: bpm)
        snapshot.minHeartRate = hr?.minimumQuantity()?.doubleValue(for: bpm)
        snapshot.maxHeartRate = hr?.maximumQuantity()?.doubleValue(for: bpm)

        let ms = HKUnit.secondUnit(with: .milli)
        snapshot.hrv = await statistic(.heartRateVariabilitySDNN, unit: ms, options: .discreteAverage, from: start, to: end)?
            .averageQuantity()?.doubleValue(for: ms)
        snapshot.steps = await statistic(.stepCount, unit: .count(), options: .cumulativeSum, from: start, to: end)?
            .sumQuantity()?.doubleValue(for: .count())
        snapshot.activeEnergy = await statistic(.activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, from: start, to: end)?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        snapshot.sleepHours = await sleepHours(endingOn: start)
        snapshot.heartRateSeries = await heartRateSeries(from: start, to: end)
        return snapshot
    }

    /// Heart rate averaged into 15-minute buckets for charting.
    private func heartRateSeries(from start: Date, to end: Date) async -> [HeartRatePoint] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let bucket: TimeInterval = 15 * 60
        var sums: [Int: (Double, Int)] = [:]
        for sample in samples {
            let key = Int(sample.startDate.timeIntervalSince(start) / bucket)
            let value = sample.quantity.doubleValue(for: bpm)
            let current = sums[key] ?? (0, 0)
            sums[key] = (current.0 + value, current.1 + 1)
        }
        return sums.keys.sorted().map { key in
            let (sum, count) = sums[key]!
            return HeartRatePoint(date: start.addingTimeInterval(Double(key) * bucket + bucket / 2), bpm: sum / Double(count))
        }
    }

    /// Sleep between 18:00 the previous evening and 12:00 on `day`, with overlapping sources merged.
    private func sleepHours(endingOn day: Date) async -> Double? {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .hour, value: -6, to: day)!
        let windowEnd = calendar.date(byAdding: .hour, value: 12, to: day)!
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        let asleep = samples.filter { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
            return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
        }
        guard !asleep.isEmpty else { return nil }

        var total: TimeInterval = 0
        var currentStart = asleep[0].startDate
        var currentEnd = asleep[0].endDate
        for sample in asleep.dropFirst() {
            if sample.startDate <= currentEnd {
                currentEnd = max(currentEnd, sample.endDate)
            } else {
                total += currentEnd.timeIntervalSince(currentStart)
                currentStart = sample.startDate
                currentEnd = sample.endDate
            }
        }
        total += currentEnd.timeIntervalSince(currentStart)
        return total / 3600
    }
}
