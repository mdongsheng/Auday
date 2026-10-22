import Foundation
import Security

/// A ready-made OpenAI-compatible endpoint. Any other compatible service works through "Custom".
struct ModelPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String
    let requiresKey: Bool

    static let all: [ModelPreset] = [
        ModelPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", requiresKey: true),
        ModelPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat", requiresKey: true),
        ModelPreset(id: "qwen", name: "通义千问 Qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", requiresKey: true),
        ModelPreset(id: "moonshot", name: "Kimi (Moonshot)", baseURL: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-8k", requiresKey: true),
        ModelPreset(id: "zhipu", name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-flash", requiresKey: true),
        ModelPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", requiresKey: true),
        ModelPreset(id: "ollama", name: "Ollama (LAN)", baseURL: "http://192.168.1.10:11434/v1", defaultModel: "qwen2.5", requiresKey: false),
        ModelPreset(id: "custom", name: "Custom", baseURL: "", defaultModel: "", requiresKey: false),
    ]

    static func find(_ id: String) -> ModelPreset? {
        all.first { $0.id == id }
    }
}

/// The user's model configuration. The API key lives in the Keychain; everything else in UserDefaults.
@MainActor
@Observable
final class ModelSettings {
    static let shared = ModelSettings()

    private static let defaults = UserDefaults.standard

    var presetID: String = UserDefaults.standard.string(forKey: "model.preset") ?? "openai" {
        didSet { Self.defaults.set(presetID, forKey: "model.preset") }
    }

    var baseURL: String = UserDefaults.standard.string(forKey: "model.baseURL") ?? "https://api.openai.com/v1" {
        didSet { Self.defaults.set(baseURL, forKey: "model.baseURL") }
    }

    var model: String = UserDefaults.standard.string(forKey: "model.name") ?? "gpt-4o-mini" {
        didSet { Self.defaults.set(model, forKey: "model.name") }
    }

    var temperature: Double = UserDefaults.standard.object(forKey: "model.temperature") as? Double ?? 0.4 {
        didSet { Self.defaults.set(temperature, forKey: "model.temperature") }
    }

    var apiKey: String = Keychain.get("model.apiKey") ?? "" {
        didSet { Keychain.set(apiKey, for: "model.apiKey") }
    }

    var preset: ModelPreset? { ModelPreset.find(presetID) }

    var isConfigured: Bool {
        let hasEndpoint = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.scheme != nil
        let needsKey = preset?.requiresKey ?? false
        return hasEndpoint && !model.trimmingCharacters(in: .whitespaces).isEmpty && (!needsKey || !apiKey.isEmpty)
    }

    func apply(presetID id: String) {
        presetID = id
        guard let preset = ModelPreset.find(id), id != "custom" else { return }
        baseURL = preset.baseURL
        model = preset.defaultModel
    }

    func makeClient() throws -> OpenAICompatibleClient {
        guard isConfigured else { throw LLMError.notConfigured }
        return OpenAICompatibleClient(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model.trimmingCharacters(in: .whitespaces),
            temperature: temperature
        )
    }
}

enum Keychain {
    private static let service = "com.mdongsheng.auday"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, for account: String) {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
