import Foundation
import Speech

struct TranscriptionResult {
    struct Segment {
        let offset: TimeInterval
        let duration: TimeInterval
        let text: String
    }

    let text: String
    let segments: [Segment]
    let localeIdentifier: String
}

enum TranscriberError: LocalizedError {
    case notAuthorized
    case unavailable(String)
    case onDeviceUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(localized: "Speech recognition permission is required.")
        case let .unavailable(locale):
            String(localized: "Speech recognition is unavailable for \(locale).")
        case let .onDeviceUnsupported(locale):
            String(localized: "On-device recognition is not supported for \(locale). Disable “On-device only” in Settings to use Apple’s server.")
        }
    }
}

/// Wraps SFSpeechRecognizer; prefers on-device recognition so audio never leaves the iPhone.
enum Transcriber {
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    static func locale(for setting: String) -> Locale {
        if setting != "auto" { return Locale(identifier: setting) }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true
            ? Locale(identifier: "zh-CN")
            : Locale(identifier: "en-US")
    }

    static func transcribe(url: URL, locale: Locale, onDeviceOnly: Bool) async throws -> TranscriptionResult {
        guard isAuthorized else { throw TranscriberError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriberError.unavailable(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if onDeviceOnly {
            throw TranscriberError.onDeviceUnsupported(locale.identifier)
        }

        let joiner = ["zh", "ja", "ko"].contains(where: { locale.identifier.hasPrefix($0) }) ? "" : " "
        let identifier = locale.identifier

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: build(result.bestTranscription, joiner: joiner, locale: identifier))
                } else if let error {
                    finished = true
                    let nsError = error as NSError
                    // 1110 = "No speech detected": a silent clip is not a failure.
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        continuation.resume(returning: TranscriptionResult(text: "", segments: [], localeIdentifier: identifier))
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Groups word-level segments into sentence-sized chunks for a readable, seekable transcript.
    private static func build(_ transcription: SFTranscription, joiner: String, locale: String) -> TranscriptionResult {
        var segments: [TranscriptionResult.Segment] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        let terminators: Set<Character> = [".", "?", "!", "。", "？", "！"]

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append(.init(offset: start, duration: end - start, text: trimmed))
            }
            text = ""
        }

        for word in transcription.segments {
            if text.isEmpty {
                start = word.timestamp
            } else if word.timestamp - end > 1.2 || end - start > 15 {
                flush()
                start = word.timestamp
            }
            text += (text.isEmpty ? "" : joiner) + word.substring
            end = word.timestamp + word.duration
            if let last = word.substring.last, terminators.contains(last) {
                flush()
            }
        }
        flush()

        return TranscriptionResult(text: transcription.formattedString, segments: segments, localeIdentifier: locale)
    }
}
