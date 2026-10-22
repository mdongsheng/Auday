import SwiftData
import SwiftUI

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudioPlayer()
    @State private var isSummarizing = false
    @State private var actionError: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                playerCard
                summaryCard
                if !recording.highlights.isEmpty { highlightsCard }
                transcriptCard
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menu }
        .onAppear { player.load(recording.fileURL) }
        .onDisappear { player.stop() }
        .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.startedAt.formatted(date: .complete, time: .shortened))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(recording.displayTitle)
                .font(Theme.display(26))
            FlowBadges(recording: recording)
        }
        .padding(.top, 8)
    }

    private var playerCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Theme.accentGradient, in: Circle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                        in: 0...max(player.duration, 1)
                    )
                    HStack {
                        Text(Format.clock(player.currentTime))
                        Spacer()
                        Text(Format.clock(player.duration))
                    }
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GradientIcon(systemName: "sparkles", size: 26, gradient: Theme.calmGradient)
                Text("Summary").font(Theme.headline)
                Spacer()
                if isSummarizing || recording.status == .summarizing {
                    ProgressView()
                }
            }
            if !recording.summary.isEmpty {
                MarkdownText(text: recording.summary).font(.callout)
            } else if recording.transcript.isEmpty {
                Text("A summary appears after transcription.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if ModelSettings.shared.isConfigured {
                Button("Summarize now") { Task { await summarize() } }
                    .disabled(isSummarizing)
            } else {
                Text("Connect an AI model in Settings to summarize recordings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = actionError ?? recording.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .card()
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights").font(Theme.headline)
            ForEach(recording.highlights) { highlight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.orange).padding(.top, 3)
                    Text(highlight.text).font(.callout)
                }
            }
        }
        .card()
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript").font(Theme.headline)
                Spacer()
                if let code = recording.languageCode {
                    Text(code).font(Theme.mono).foregroundStyle(.secondary)
                }
            }
            switch recording.status {
            case .pending, .transcribing:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Transcribing on device…").foregroundStyle(.secondary)
                }
            case .failed:
                Button("Try again") { ProcessingQueue.shared.retranscribe(recording) }
            default:
                if recording.segments.isEmpty {
                    Text(recording.transcript.isEmpty ? String(localized: "No speech detected.") : recording.transcript)
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    ForEach(recording.sortedSegments) { segment in
                        let isCurrent = player.isPlaying
                            && player.currentTime >= segment.offset
                            && player.currentTime < segment.offset + max(segment.duration, 1)
                        Button {
                            player.seek(to: segment.offset)
                            player.play()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(Format.clock(segment.offset))
                                    .font(Theme.mono)
                                    .foregroundStyle(isCurrent ? Theme.pink : .secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(segment.text)
                                    .font(.callout)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    recording.isStarred.toggle()
                } label: {
                    Label(recording.isStarred ? LocalizedStringKey("Unstar") : LocalizedStringKey("Star"), systemImage: recording.isStarred ? "star.slash" : "star")
                }
                Button {
                    ProcessingQueue.shared.retranscribe(recording)
                } label: {
                    Label("Transcribe again", systemImage: "text.bubble")
                }
                Button {
                    Task { await summarize() }
                } label: {
                    Label("Summarize again", systemImage: "sparkles")
                }
                .disabled(recording.transcript.isEmpty || !ModelSettings.shared.isConfigured)
                ShareLink(item: recording.fileURL) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func summarize() async {
        isSummarizing = true
        actionError = nil
        do {
            try await ProcessingQueue.shared.resummarize(recording)
        } catch {
            actionError = error.localizedDescription
        }
        isSummarizing = false
    }

    private func delete() {
        player.stop()
        AudioStorage.delete(recording.fileName)
        context.delete(recording)
        try? context.save()
        dismiss()
    }
}
