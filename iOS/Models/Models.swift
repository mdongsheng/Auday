import Foundation
import SwiftData

enum RecordingStatus: String, Codable {
    case pending, transcribing, transcribed, summarizing, done, failed
}

enum RecordingSource: String, Codable {
    case watch, phone
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var duration: TimeInterval
    var fileName: String
    var sourceRaw: String
    var sessionID: UUID?
    var statusRaw: String
    var errorMessage: String?
    var transcript: String
    var languageCode: String?
    var title: String
    var summary: String
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var avgHeartRate: Double?
    var stressLevel: Double?
    var isStarred: Bool

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
    var segments: [TranscriptSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.recording)
    var highlights: [Highlight] = []

    init(
        startedAt: Date,
        duration: TimeInterval,
        fileName: String,
        source: RecordingSource,
        sessionID: UUID? = nil,
        avgHeartRate: Double? = nil
    ) {
        self.id = UUID()
        self.startedAt = startedAt
        self.duration = duration
        self.fileName = fileName
        self.sourceRaw = source.rawValue
        self.sessionID = sessionID
        self.statusRaw = RecordingStatus.pending.rawValue
        self.transcript = ""
        self.title = ""
        self.summary = ""
        self.avgHeartRate = avgHeartRate
        self.isStarred = false
    }

    var status: RecordingStatus {
        get { RecordingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var source: RecordingSource {
        RecordingSource(rawValue: sourceRaw) ?? .phone
    }

    var endedAt: Date { startedAt.addingTimeInterval(duration) }

    var fileURL: URL { AudioStorage.url(for: fileName) }

    var sortedSegments: [TranscriptSegment] {
        segments.sorted { $0.offset < $1.offset }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let preview = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty { return String(preview.prefix(40)) }
        return String(localized: "Recording at \(Format.time(startedAt))")
    }
}

@Model
final class TranscriptSegment {
    var offset: TimeInterval
    var duration: TimeInterval
    var text: String
    var recording: Recording?

    init(offset: TimeInterval, duration: TimeInterval, text: String) {
        self.offset = offset
        self.duration = duration
        self.text = text
    }
}

@Model
final class Highlight {
    var text: String
    var date: Date
    var recording: Recording?

    init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

@Model
final class DayReflection {
    @Attribute(.unique) var day: Date
    var content: String
    var generatedAt: Date

    init(day: Date, content: String) {
        self.day = day
        self.content = content
        self.generatedAt = .now
    }
}

@Model
final class ChatMessage {
    var role: String
    var content: String
    var createdAt: Date
    var citations: [UUID]

    init(role: String, content: String, citations: [UUID] = []) {
        self.role = role
        self.content = content
        self.createdAt = .now
        self.citations = citations
    }

    var isUser: Bool { role == "user" }
}

@MainActor
enum Persistence {
    static let container: ModelContainer = {
        let schema = Schema([
            Recording.self,
            TranscriptSegment.self,
            Highlight.self,
            DayReflection.self,
            ChatMessage.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}

enum AudioStorage {
    static var directory: URL {
        let url = URL.documentsDirectory.appending(path: "Audio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    static func newFileName(ext: String = "m4a") -> String {
        "\(UUID().uuidString).\(ext)"
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func totalBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
