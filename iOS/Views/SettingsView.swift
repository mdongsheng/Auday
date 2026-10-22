import AVFoundation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable private var settings = AppSettings.shared
    @Query private var recordings: [Recording]
    @State private var storageBytes: Int64 = 0
    @State private var confirmDeleteAll = false

    private var models: ModelSettings { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ModelSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            GradientIcon(systemName: "cpu", size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Model")
                                Text(models.isConfigured ? "\(models.preset?.name ?? "") · \(models.model)" : String(localized: "Not configured"))
                                    .font(.caption)
                                    .foregroundStyle(models.isConfigured ? Color.secondary : Color.orange)
                            }
                        }
                    }
                    Toggle("Summarize automatically", isOn: $settings.autoSummarize)
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text("Only transcript text is sent to the model you configure. Audio never leaves your devices.")
                }

                Section("Recording & Transcription") {
                    Picker("Language", selection: $settings.transcriptionLocale) {
                        Text("Automatic").tag("auto")
                        Text(verbatim: "简体中文").tag("zh-CN")
                        Text(verbatim: "English").tag("en-US")
                    }
                    Toggle("On-device only", isOn: $settings.onDeviceOnly)
                    Picker("Chunk length", selection: $settings.chunkMinutes) {
                        ForEach([1, 2, 5, 10], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Toggle("Tag location", isOn: $settings.tagLocation)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Permissions") {
                    Button("Microphone") { Task { _ = await AVAudioApplication.requestRecordPermission() } }
                    Button("Speech Recognition") { Task { _ = await Transcriber.requestAuthorization() } }
                    Button("Health") { Task { _ = await HealthStore.shared.requestAuthorization() } }
                    Button("Location") { LocationTracker.shared.requestAuthorization() }
                    Button("Open System Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Data") {
                    LabeledContent("Recordings", value: "\(recordings.count)")
                    LabeledContent("Audio storage", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                    NavigationLink("Privacy") { PrivacyView() }
                    Button("Delete all data", role: .destructive) { confirmDeleteAll = true }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                } footer: {
                    Text("Inspired by Auday. No servers, no accounts — your memories stay yours.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { storageBytes = AudioStorage.totalBytes() }
            .confirmationDialog("Delete all recordings, transcripts and chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAll)
            }
        }
    }

    private func deleteAll() {
        try? FileManager.default.removeItem(at: AudioStorage.directory)
        try? context.delete(model: TranscriptSegment.self)
        try? context.delete(model: Highlight.self)
        try? context.delete(model: Recording.self)
        try? context.delete(model: DayReflection.self)
        try? context.delete(model: ChatMessage.self)
        try? context.save()
        storageBytes = AudioStorage.totalBytes()
    }
}

struct ModelSettingsView: View {
    @Bindable private var models = ModelSettings.shared
    @State private var availableModels: [String] = []
    @State private var isTesting = false
    @State private var isFetching = false
    @State private var testResult: (success: Bool, message: String)?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: Binding(get: { models.presetID }, set: { models.apply(presetID: $0) })) {
                    ForEach(ModelPreset.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            } footer: {
                Text("Any service compatible with the OpenAI Chat Completions API works, including self-hosted Ollama, vLLM or LM Studio.")
            }

            Section("Endpoint") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL").font(.caption).foregroundStyle(.secondary)
                    TextField(text: $models.baseURL, prompt: Text(verbatim: "https://api.example.com/v1")) {
                        Text("Base URL")
                    }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key").font(.caption).foregroundStyle(.secondary)
                    SecureField(text: $models.apiKey, prompt: Text(verbatim: "sk-…")) {
                        Text("API Key")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField(text: $models.model, prompt: Text(verbatim: "gpt-4o-mini")) {
                            Text("Model")
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        if isFetching {
                            ProgressView()
                        } else {
                            Menu {
                                if availableModels.isEmpty {
                                    Button("Fetch model list") { Task { await fetchModels() } }
                                } else {
                                    ForEach(availableModels, id: \.self) { name in
                                        Button(name) { models.model = name }
                                    }
                                    Divider()
                                    Button("Refresh list") { Task { await fetchModels() } }
                                }
                            } label: {
                                Image(systemName: "list.bullet.circle")
                            }
                        }
                    }
                }
            }

            Section("Parameters") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", models.temperature)).font(Theme.mono).foregroundStyle(.secondary)
                    }
                    Slider(value: $models.temperature, in: 0...1.5, step: 0.1)
                }
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || !models.isConfigured)
                if let testResult {
                    Label(testResult.message, systemImage: testResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(testResult.success ? Color.green : Color.red)
                        .font(.footnote)
                }
            } footer: {
                Text("Your API key is stored in the iOS Keychain on this device only.")
            }
        }
        .navigationTitle("AI Model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let reply = try await models.makeClient().complete([
                .system("You are a connection test. Reply with one short friendly sentence."),
                .user("Hello from Auday!"),
            ])
            testResult = (true, reply)
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }

    private func fetchModels() async {
        isFetching = true
        defer { isFetching = false }
        do {
            let client = OpenAICompatibleClient(baseURL: models.baseURL, apiKey: models.apiKey, model: models.model, temperature: models.temperature)
            availableModels = try await client.listModels()
            if availableModels.isEmpty { testResult = (false, String(localized: "The endpoint returned no models.")) }
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                item("iphone", "Stays on your devices", "Audio recordings, transcripts, health data, places and chat history are stored only on your iPhone. There is no Auday server or account.")
                item("waveform.badge.mic", "On-device transcription", "Speech is transcribed by Apple’s on-device recognizer. With “On-device only” enabled, audio is never sent anywhere.")
                item("paperplane", "What is sent to your model", "When you summarize, reflect or chat, the relevant transcript text and short health/place context are sent directly from your iPhone to the endpoint you configured — never the audio.")
                item("key", "Your key, your provider", "Your API key is kept in the Keychain and only used to call your chosen provider. Their privacy policy applies to that text.")
                item("trash", "Delete anytime", "Delete single recordings, or everything from Settings → Data.")
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Privacy")
    }

    private func item(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GradientIcon(systemName: icon, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
