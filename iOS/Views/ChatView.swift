import SwiftData
import SwiftUI

struct ChatView: View {
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @State private var input = ""
    @State private var confirmClear = false
    @FocusState private var isFocused: Bool

    private var engine: ChatEngine { .shared }
    private var models: ModelSettings { .shared }

    private var suggestions: [String] {
        [
            String(localized: "What did I talk about today?"),
            String(localized: "Summarize yesterday's meetings"),
            String(localized: "What tasks did I agree to this week?"),
            String(localized: "When was I most stressed today?"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !models.isConfigured { setupBanner }
                        if messages.isEmpty && !engine.isStreaming { emptyState }
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                        if engine.isStreaming {
                            StreamingBubble(text: engine.streamingText)
                        }
                        if let error = engine.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: engine.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ask Auday")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { RecordingLookupView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty)
                }
            }
            .confirmationDialog("Clear the conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { engine.clear() }
            }
        }
    }

    private var setupBanner: some View {
        NavigationLink {
            ModelSettingsView()
        } label: {
            HStack(spacing: 12) {
                GradientIcon(systemName: "key.fill", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect a model").font(Theme.headline)
                    Text("Add an OpenAI-compatible endpoint and key to start chatting.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            GradientIcon(systemName: "sparkles", size: 48, gradient: Theme.calmGradient)
                .padding(.top, 24)
            Text("Ask anything about your day")
                .font(Theme.display(24))
            Text("Answers come from your own recordings, with links to the moments they came from.")
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    HStack {
                        Text(suggestion).font(.callout)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .foregroundStyle(.primary)
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
                .disabled(!models.isConfigured)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your recordings…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onSubmit { send() }
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentGradient, in: Circle())
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.isStreaming || !models.isConfigured)
            .opacity(input.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ suggestion: String? = nil) {
        let text: String
        if let suggestion {
            text = suggestion
        } else {
            text = input
            input = ""
        }
        Task { await engine.send(text) }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                MarkdownText(text: message.content)
                    .textSelection(.enabled)
                if !message.citations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(message.citations.enumerated()), id: \.offset) { index, id in
                                CitationChip(index: index + 1, id: id)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.trailing, 32)
        }
    }
}

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            if text.isEmpty {
                ProgressView()
            } else {
                MarkdownText(text: text)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 32)
    }
}

struct CitationChip: View {
    let index: Int
    @Query private var matches: [Recording]

    init(index: Int, id: UUID) {
        self.index = index
        _matches = Query(filter: #Predicate<Recording> { $0.id == id })
    }

    var body: some View {
        if let recording = matches.first {
            NavigationLink(value: recording.id) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text(verbatim: "\(index) · \(Format.time(recording.startedAt))")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.pink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.pink.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct RecordingLookupView: View {
    @Query private var matches: [Recording]

    init(id: UUID) {
        _matches = Query(filter: #Predicate<Recording> { $0.id == id })
    }

    var body: some View {
        if let recording = matches.first {
            RecordingDetailView(recording: recording)
        } else {
            ContentUnavailableView("Recording deleted", systemImage: "trash")
        }
    }
}
