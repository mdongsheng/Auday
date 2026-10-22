import AVFoundation
import Foundation

/// Records on the iPhone in fixed-length chunks so long sessions are transcribed progressively.
@MainActor
@Observable
final class PhoneRecorder {
    static let shared = PhoneRecorder()

    private(set) var isRecording = false
    private(set) var sessionStart: Date?
    private(set) var level: Float = 0
    var lastError: String?

    private var recorder: AVAudioRecorder?
    private var chunkStart: Date?
    private var chunkFile: String?
    private var sessionID = UUID()
    private var chunkTimer: Timer?
    private var meterTimer: Timer?

    static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        guard !isRecording else { return }
        lastError = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = String(localized: "Microphone access is off. Enable it in Settings.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
            return
        }

        sessionID = UUID()
        sessionStart = .now
        isRecording = true
        startChunk()

        let chunkSeconds = TimeInterval(max(1, AppSettings.shared.chunkMinutes) * 60)
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateChunk() }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
        isRecording = false
        sessionStart = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startChunk() {
        let name = AudioStorage.newFileName()
        do {
            let recorder = try AVAudioRecorder(url: AudioStorage.url(for: name), settings: Self.audioSettings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                lastError = String(localized: "Could not start recording.")
                return
            }
            self.recorder = recorder
            chunkStart = .now
            chunkFile = name
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func finishChunk() {
        guard let recorder, let chunkStart, let chunkFile else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.chunkStart = nil
        self.chunkFile = nil
        if duration >= 1 {
            RecordingIngest.add(
                fileName: chunkFile,
                startedAt: chunkStart,
                duration: duration,
                source: .phone,
                sessionID: sessionID
            )
        } else {
            AudioStorage.delete(chunkFile)
        }
    }

    private func rotateChunk() {
        guard isRecording else { return }
        finishChunk()
        startChunk()
    }

    private func updateLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // -160…0 dB
        level = max(0, min(1, (power + 50) / 50))
    }
}

/// Simple audio player for a recording, with a published playhead for transcript sync.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if !PhoneRecorder.shared.isRecording {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        pause()
        player?.stop()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = max(0, min(time, duration))
        currentTime = player?.currentTime ?? 0
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            timer?.invalidate()
        }
    }
}
