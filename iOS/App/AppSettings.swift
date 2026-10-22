import SwiftUI

/// User preferences persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private static let defaults = UserDefaults.standard

    var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: "hasOnboarded") {
        didSet { Self.defaults.set(hasOnboarded, forKey: "hasOnboarded") }
    }

    /// "auto", "zh-CN" or "en-US".
    var transcriptionLocale: String = UserDefaults.standard.string(forKey: "transcriptionLocale") ?? "auto" {
        didSet { Self.defaults.set(transcriptionLocale, forKey: "transcriptionLocale") }
    }

    var onDeviceOnly: Bool = UserDefaults.standard.object(forKey: "onDeviceOnly") as? Bool ?? true {
        didSet { Self.defaults.set(onDeviceOnly, forKey: "onDeviceOnly") }
    }

    var autoSummarize: Bool = UserDefaults.standard.object(forKey: "autoSummarize") as? Bool ?? true {
        didSet { Self.defaults.set(autoSummarize, forKey: "autoSummarize") }
    }

    var tagLocation: Bool = UserDefaults.standard.object(forKey: "tagLocation") as? Bool ?? true {
        didSet { Self.defaults.set(tagLocation, forKey: "tagLocation") }
    }

    var chunkMinutes: Int = UserDefaults.standard.object(forKey: "chunkMinutes") as? Int ?? 5 {
        didSet { Self.defaults.set(chunkMinutes, forKey: "chunkMinutes") }
    }

    /// "system", "dark" or "light". Auday is dark-first.
    var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "dark" {
        didSet { Self.defaults.set(appearance, forKey: "appearance") }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}
