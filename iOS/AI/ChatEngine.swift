import Foundation
import SwiftData

struct ChatContext {
    let text: String
    let references: [(label: String, id: UUID)]

    /// The recordings the answer actually cited, in citation order.
    func cited(in answer: String) -> [UUID] {
        references.filter { answer.contains("[\($0.label)]") }.map(\.id)
    }
}

/// Picks the recordings most relevant to a question and formats them for the prompt.
@MainActor
enum ChatContextBuilder {
    static func dateRange(for question: String, now: Date = .now) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let q = question.lowercased()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func has(_ words: [String]) -> Bool { words.contains { q.contains($0) } }

        if has(["day before yesterday", "前天"]) { return (day(-2), day(-1)) }
        if has(["yesterday", "昨天", "昨日"]) { return (day(-1), day(0)) }
        if has(["today", "this morning", "this afternoon", "tonight", "今天", "今日", "上午", "下午", "今晚"]) {
            return (day(0), day(1))
        }
        if has(["last week", "上周", "上个星期"]) {
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return (calendar.date(byAdding: .day, value: -7, to: thisWeek)!, thisWeek)
        }
        if has(["this week", "本周", "这周", "这个星期", "最近", "recently", "lately"]) {
            return (calendar.dateInterval(of: .weekOfYear, for: now)!.start, day(1))
        }
        return nil
    }

    static func keywords(_ question: String) -> [String] {
        let stop: Set<String> = [
            "what", "when", "where", "who", "did", "does", "the", "and", "for", "with", "about", "that",
            "this", "have", "was", "were", "you", "your", "how", "today", "yesterday", "week",
            "什么", "怎么", "哪里", "今天", "昨天", "我们", "你们", "一下", "是否", "有没", "没有", "时候",
        ]
        var result: [String] = []
        let tokens = question.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        for token in tokens where !token.isEmpty {
            if token.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                // No word boundaries in Chinese: use overlapping bigrams.
                let chars = Array(token)
                if chars.count == 1 { continue }
                for i in 0..<(chars.count - 1) {
                    let gram = String(chars[i...i + 1])
                    if !stop.contains(gram) { result.append(gram) }
                }
            } else if token.count >= 3, !stop.contains(token) {
                result.append(token)
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func build(for question: String, budget: Int = 12_000) -> ChatContext {
        let context = Persistence.context
        let explicitRange = dateRange(for: question)
        let now = Date.now
        let start = explicitRange?.start ?? Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let end = explicitRange?.end ?? now.addingTimeInterval(60)

        var descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        let recordings = (try? context.fetch(descriptor)) ?? []
        let words = keywords(question)

        let scored: [(Recording, Int)] = recordings.map { recording in
            let haystack = (recording.title + " " + recording.summary + " " + recording.transcript).lowercased()
            let hits = words.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
            return (recording, hits)
        }
        let anyHits = scored.contains { $0.1 > 0 }
        let ranked: [Recording]
        if anyHits && explicitRange == nil {
            ranked = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        } else if anyHits {
            ranked = scored.sorted { $0.1 > $1.1 }.map(\.0)
        } else {
            ranked = recordings
        }

        var text = ""
        var refs: [(label: String, id: UUID)] = []
        for recording in ranked {
            let label = "R\(refs.count + 1)"
            var entry = "[\(label)] \(recording.startedAt.formatted(date: .abbreviated, time: .shortened))"
            entry += " · \(Format.duration(recording.duration))"
            if let place = recording.placeName { entry += " · \(place)" }
            if let hr = recording.avgHeartRate { entry += " · \(Int(hr)) bpm" }
            entry += "\n"
            if !recording.title.isEmpty { entry += "Title: \(recording.title)\n" }
            if !recording.summary.isEmpty { entry += "Summary: \(recording.summary)\n" }
            let excerpt = excerpt(of: recording.transcript, around: words, length: recording.summary.isEmpty ? 1500 : 700)
            if !excerpt.isEmpty { entry += "Transcript: \(excerpt)\n" }
            entry += "\n"
            if text.count + entry.count > budget { break }
            text += entry
            refs.append((label: label, id: recording.id))
        }
        return ChatContext(text: text, references: refs)
    }

    private static func excerpt(of transcript: String, around words: [String], length: Int) -> String {
        guard transcript.count > length else { return transcript }
        let lower = transcript.lowercased()
        if let word = words.first(where: { lower.contains($0) }), let range = lower.range(of: word) {
            let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let startOffset = max(0, offset - length / 3)
            let startIndex = transcript.index(transcript.startIndex, offsetBy: startOffset)
            let endIndex = transcript.index(startIndex, offsetBy: length, limitedBy: transcript.endIndex) ?? transcript.endIndex
            return "…" + String(transcript[startIndex..<endIndex]) + "…"
        }
        return String(transcript.prefix(length)) + "…"
    }
}

@MainActor
@Observable
final class ChatEngine {
    static let shared = ChatEngine()

    private(set) var isStreaming = false
    private(set) var streamingText = ""
    var lastError: String?

    private var history: [LLMMessage] {
        var descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 8
        let recent = (try? Persistence.context.fetch(descriptor)) ?? []
        return recent.reversed().map { LLMMessage(role: $0.role, content: $0.content) }
    }

    func send(_ question: String) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        lastError = nil

        let client: OpenAICompatibleClient
        do { client = try ModelSettings.shared.makeClient() } catch {
            lastError = error.localizedDescription
            return
        }

        let context = Persistence.context
        let previous = history
        context.insert(ChatMessage(role: "user", content: text))
        try? context.save()

        let built = ChatContextBuilder.build(for: text)
        let messages = [LLMMessage.system(Prompts.chat(context: built.text))] + previous + [.user(text)]

        isStreaming = true
        streamingText = ""
        do {
            for try await delta in client.stream(messages) {
                streamingText += delta
            }
        } catch {
            lastError = error.localizedDescription
        }
        let answer = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            context.insert(ChatMessage(role: "assistant", content: answer, citations: built.cited(in: answer)))
            try? context.save()
        }
        isStreaming = false
        streamingText = ""
    }

    /// Short, non-streaming answer for the Watch.
    func answerForWatch(_ question: String) async throws -> String {
        let client = try ModelSettings.shared.makeClient()
        let built = ChatContextBuilder.build(for: question, budget: 8_000)
        let answer = try await client.complete([
            .system(Prompts.chat(context: built.text) + "\n\n" + Prompts.watchSuffix),
            .user(question),
        ])
        let context = Persistence.context
        context.insert(ChatMessage(role: "user", content: question))
        context.insert(ChatMessage(role: "assistant", content: answer, citations: built.cited(in: answer)))
        try? context.save()
        return answer
    }

    func clear() {
        try? Persistence.context.delete(model: ChatMessage.self)
        try? Persistence.context.save()
    }
}
