import BackgroundTasks
import Foundation
import SwiftData

/// Creates `Recording`s from finished audio chunks (Watch or iPhone) and tags them with place.
@MainActor
enum RecordingIngest {
    static func add(
        fileName: String,
        startedAt: Date,
        duration: TimeInterval,
        source: RecordingSource,
        sessionID: UUID?,
        heartRate: Double? = nil
    ) {
        let context = Persistence.context
        let recording = Recording(
            startedAt: startedAt,
            duration: duration,
            fileName: fileName,
            source: source,
            sessionID: sessionID,
            avgHeartRate: heartRate
        )
        context.insert(recording)
        try? context.save()

        Task {
            if AppSettings.shared.tagLocation, let place = await LocationTracker.shared.currentPlace() {
                recording.placeName = place.name
                recording.latitude = place.latitude
                recording.longitude = place.longitude
                try? context.save()
            }
            ProcessingQueue.shared.enqueue()
        }
    }
}

/// Serially transcribes new recordings, enriches them with health data and summarizes them.
@MainActor
@Observable
final class ProcessingQueue {
    static let shared = ProcessingQueue()

    private(set) var isRunning = false
    private(set) var currentTitle: String?

    func enqueue() {
        Task { await processPending() }
    }

    func processPending() async {
        guard !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            currentTitle = nil
        }
        var attempted = Set<UUID>()
        while let next = nextJob(excluding: attempted) {
            attempted.insert(next.id)
            await process(next)
        }
    }

    private var canSummarize: Bool {
        AppSettings.shared.autoSummarize && ModelSettings.shared.isConfigured
    }

    private func nextJob(excluding attempted: Set<UUID>) -> Recording? {
        let pending = RecordingStatus.pending.rawValue
        let transcribed = RecordingStatus.transcribed.rawValue
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.statusRaw == pending || $0.statusRaw == transcribed },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let candidates = (try? Persistence.context.fetch(descriptor)) ?? []
        return candidates.first { recording in
            !attempted.contains(recording.id) && (recording.status == .pending || canSummarize)
        }
    }

    private func process(_ recording: Recording) async {
        currentTitle = Format.time(recording.startedAt)
        if recording.status == .pending {
            await transcribe(recording)
            await enrich(recording)
        }
        if recording.status == .transcribed && canSummarize {
            await summarize(recording)
        }
        try? Persistence.context.save()
    }

    private func transcribe(_ recording: Recording) async {
        recording.status = .transcribing
        let settings = AppSettings.shared
        do {
            let result = try await Transcriber.transcribe(
                url: recording.fileURL,
                locale: Transcriber.locale(for: settings.transcriptionLocale),
                onDeviceOnly: settings.onDeviceOnly
            )
            let context = recording.modelContext ?? Persistence.context
            for old in recording.segments { context.delete(old) }
            for segment in result.segments {
                let model = TranscriptSegment(offset: segment.offset, duration: segment.duration, text: segment.text)
                context.insert(model)
                model.recording = recording
            }
            recording.transcript = result.text
            recording.languageCode = result.localeIdentifier
            recording.errorMessage = nil
            // Nothing to summarize in a silent clip.
            recording.status = result.text.isEmpty ? .done : .transcribed
        } catch {
            recording.errorMessage = error.localizedDescription
            recording.status = .failed
        }
    }

    private func enrich(_ recording: Recording) async {
        let health = HealthStore.shared
        guard health.isAvailable else { return }
        if recording.avgHeartRate == nil {
            recording.avgHeartRate = await health.averageHeartRate(from: recording.startedAt, to: recording.endedAt)
        }
        recording.stressLevel = await health.stressEstimate(from: recording.startedAt, to: recording.endedAt)
    }

    private func summarize(_ recording: Recording) async {
        recording.status = .summarizing
        do {
            try await Summarizer.summarize(recording)
            recording.errorMessage = nil
        } catch {
            // Keep the transcript; the user can retry from the detail screen.
            recording.errorMessage = error.localizedDescription
        }
        recording.status = .done
    }

    func retranscribe(_ recording: Recording) {
        recording.status = .pending
        try? Persistence.context.save()
        enqueue()
    }

    func resummarize(_ recording: Recording) async throws {
        recording.status = .summarizing
        defer { recording.status = .done }
        try await Summarizer.summarize(recording)
        recording.errorMessage = nil
    }
}

/// Lets the queue finish transcription while the app is in the background.
enum BackgroundProcessing {
    static let identifier = "com.mdongsheng.auday.process"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task { @MainActor in
                await ProcessingQueue.shared.processPending()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
