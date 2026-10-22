import Foundation
import SwiftData

@MainActor
enum Summarizer {
    private struct Output: Decodable {
        let title: String?
        let summary: String?
        let highlights: [String]?
    }

    /// Asks the model for a title, summary and highlights. Only transcript text is sent; audio never leaves the device.
    static func summarize(_ recording: Recording) async throws {
        let transcript = recording.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        let client = try ModelSettings.shared.makeClient()

        var input = "Recorded: \(recording.startedAt.formatted(date: .abbreviated, time: .shortened))"
        input += " · \(Format.duration(recording.duration))"
        if let place = recording.placeName { input += "\nPlace: \(place)" }
        if let hr = recording.avgHeartRate { input += "\nAverage heart rate: \(Int(hr)) bpm" }
        input += "\n\nTranscript:\n\(transcript.prefix(12_000))"

        let reply = try await client.complete([.system(Prompts.summary), .user(input)])
        let output = parse(reply)

        recording.title = output?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recording.summary = output?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? reply

        let context = recording.modelContext ?? Persistence.context
        for old in recording.highlights { context.delete(old) }
        for text in output?.highlights ?? [] where !text.isEmpty {
            let highlight = Highlight(text: text, date: recording.startedAt)
            context.insert(highlight)
            highlight.recording = recording
        }
        try? context.save()
    }

    /// Models don't always honour "JSON only", so extract the outermost object leniently.
    private static func parse(_ text: String) -> Output? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let json = String(text[start...end])
        return try? JSONDecoder().decode(Output.self, from: Data(json.utf8))
    }
}

@MainActor
enum ReflectionGenerator {
    static func generate(for day: Date) async throws -> DayReflection {
        let client = try ModelSettings.shared.makeClient()
        let context = Persistence.context
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let recordings = (try? context.fetch(descriptor)) ?? []
        let health = await HealthStore.shared.snapshot(for: start)

        var input = "Date: \(start.formatted(date: .complete, time: .omitted))\n"
        input += "Recordings: \(recordings.count), total \(Format.duration(recordings.reduce(0) { $0 + $1.duration }))\n\n"
        input += health.promptDescription + "\n\n"

        var budget = 10_000
        for recording in recordings where budget > 0 {
            var line = "- \(Format.time(recording.startedAt))"
            if let place = recording.placeName { line += " @ \(place)" }
            if let hr = recording.avgHeartRate { line += " (\(Int(hr)) bpm)" }
            let body = recording.summary.isEmpty ? String(recording.transcript.prefix(600)) : recording.summary
            line += ": \(recording.title.isEmpty ? "" : recording.title + " — ")\(body)\n"
            budget -= line.count
            input += line
        }
        if recordings.isEmpty { input += "(No recordings today.)\n" }

        let content = try await client.complete([.system(Prompts.reflection), .user(input)])

        let existing = try? context.fetch(FetchDescriptor<DayReflection>(predicate: #Predicate { $0.day == start }))
        let reflection: DayReflection
        if let found = existing?.first {
            found.content = content
            found.generatedAt = .now
            reflection = found
        } else {
            reflection = DayReflection(day: start, content: content)
            context.insert(reflection)
        }
        try? context.save()
        return reflection
    }
}
