import AVFoundation
import Foundation
import HealthKit

struct WatchChunk: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let duration: TimeInterval
    var sent: Bool
}

/// Records on the Watch in chunks and hands each finished chunk to WatchConnectivity.
/// A workout session keeps the app running (and the mic open) with the wrist down.
@MainActor
@Observable
final class WatchRecorder {
    static let shared = WatchRecorder()

    private(set) var isRecording = false
    private(set) var sessionStart: Date?
    private(set) var heartRate: Double?
    private(set) var level: Float = 0
    var lastError: String?

    private let workout = WorkoutKeeper()
    private var recorder: AVAudioRecorder?
    private var chunkStart: Date?
    private var chunkURL: URL?
    private var chunkHeartRates: [Double] = []
    private var sessionID = UUID()
    private var chunkTimer: Timer?
    private var meterTimer: Timer?
    private var lastStatusSent = Date.distantPast

    private static let chunkSeconds: TimeInterval = 5 * 60

    private static var directory: URL {
        let url = URL.documentsDirectory.appending(path: "Outbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        workout.onHeartRate = { [weak self] bpm in
            guard let self else { return }
            heartRate = bpm
            chunkHeartRates.append(bpm)
            if Date.now.timeIntervalSince(lastStatusSent) > 5 {
                lastStatusSent = .now
                WatchLink.shared.sendStatus()
            }
        }
    }

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        guard !isRecording else { return }
        lastError = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = String(localized: "Allow microphone access in the Watch app settings.")
            return
        }
        await workout.requestAuthorization()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
            return
        }

        workout.start()
        sessionID = UUID()
        sessionStart = .now
        isRecording = true
        startChunk()
        WatchLink.shared.sendStatus()

        chunkTimer = Timer.scheduledTimer(withTimeInterval: Self.chunkSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateChunk() }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLevel() }
        }
    }

    func stop() {
        guard isRecording else { return }
        chunkTimer?.invalidate()
        meterTimer?.invalidate()
        chunkTimer = nil
        meterTimer = nil
        finishChunk()
        workout.stop()
        isRecording = false
        sessionStart = nil
        heartRate = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        WatchLink.shared.sendStatus()
    }

    private func startChunk() {
        let url = Self.directory.appending(path: "\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                lastError = String(localized: "Could not start recording.")
                return
            }
            self.recorder = recorder
            chunkStart = .now
            chunkURL = url
            chunkHeartRates = []
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func finishChunk() {
        guard let recorder, let chunkStart, let chunkURL else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.chunkStart = nil
        self.chunkURL = nil
        guard duration >= 1 else {
            try? FileManager.default.removeItem(at: chunkURL)
            return
        }
        let avgHR = chunkHeartRates.isEmpty ? nil : chunkHeartRates.reduce(0, +) / Double(chunkHeartRates.count)
        WatchLink.shared.send(
            chunk: chunkURL,
            startedAt: chunkStart,
            duration: duration,
            sessionID: sessionID,
            heartRate: avgHR
        )
    }

    private func rotateChunk() {
        guard isRecording else { return }
        finishChunk()
        startChunk()
    }

    private func updateLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
    }
}

/// Runs an HKWorkoutSession during recording for background runtime and live heart rate.
/// The workout is discarded at the end so nothing is written to Fitness.
final class WorkoutKeeper: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var onHeartRate: (@MainActor (Double) -> Void)?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [HKQuantityType(.heartRate)]
        )
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .unknown
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    func stop() {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.discardWorkout()
        }
        self.session = nil
        self.builder = nil
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.onHeartRate?(bpm) }
    }
}
