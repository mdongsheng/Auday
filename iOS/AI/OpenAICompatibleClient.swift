import Foundation

struct LLMMessage: Codable, Sendable {
    let role: String
    let content: String

    static func system(_ text: String) -> LLMMessage { LLMMessage(role: "system", content: text) }
    static func user(_ text: String) -> LLMMessage { LLMMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> LLMMessage { LLMMessage(role: "assistant", content: text) }
}

enum LLMError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "No AI model is configured. Add one in Settings → AI Model.")
        case .invalidURL:
            String(localized: "The Base URL is not valid.")
        case let .http(code, message):
            "HTTP \(code): \(message)"
        case .emptyResponse:
            String(localized: "The model returned an empty response.")
        }
    }
}

/// Minimal client for any service that implements the OpenAI Chat Completions API
/// (OpenAI, DeepSeek, Qwen, Moonshot, GLM, OpenRouter, Ollama, vLLM, LM Studio…).
struct OpenAICompatibleClient: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
    let temperature: Double

    private struct ChatBody: Encodable {
        let model: String
        let messages: [LLMMessage]
        let temperature: Double
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    private struct ModelList: Decodable {
        struct Item: Decodable { let id: String }
        let data: [Item]
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let message: String? }
        let error: Body?
    }

    private func endpoint(_ path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path), url.scheme != nil, url.host != nil else {
            throw LLMError.invalidURL
        }
        return url
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    private func chatRequest(_ messages: [LLMMessage], stream: Bool) throws -> URLRequest {
        let body = ChatBody(model: model, messages: messages, temperature: temperature, stream: stream)
        return try makeRequest(path: "/chat/completions", method: "POST", body: try JSONEncoder().encode(body))
    }

    private static func errorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message {
            return message
        }
        return String(decoding: data.prefix(400), as: UTF8.self)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, errorMessage(from: data))
        }
    }

    func complete(_ messages: [LLMMessage]) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: chatRequest(messages, stream: false))
        try Self.check(response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }

    /// Streams content deltas using server-sent events.
    func stream(_ messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(messages, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 4000 { break }
                        }
                        throw LLMError.http(http.statusCode, Self.errorMessage(from: body))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta?.content,
                              !delta.isEmpty else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [String] {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: "/models"))
        try Self.check(response, data: data)
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
    }
}
