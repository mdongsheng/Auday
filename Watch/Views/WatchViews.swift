import SwiftUI

struct RecordView: View {
    @State private var pulse = false

    private var recorder: WatchRecorder { .shared }
    private var state: WatchState { .shared }

    var body: some View {
        VStack(spacing: 8) {
            if recorder.isRecording, let start = recorder.sessionStart {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.clock(context.date.timeIntervalSince(start)))
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.pink)
                }
            } else {
                Text("Auday")
                    .font(Theme.display(20))
            }

            Button {
                Task { await recorder.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.accentGradient, lineWidth: 4)
                        .opacity(recorder.isRecording ? 0.6 : 0)
                        .scaleEffect(recorder.isRecording ? (pulse ? 1.18 : 1.0) + CGFloat(recorder.level) * 0.2 : 1)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    Circle()
                        .fill(Theme.accentGradient)
                        .padding(6)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 104, height: 104)
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction)
            .sensoryFeedback(.start, trigger: recorder.isRecording)

            HStack(spacing: 10) {
                if let hr = recorder.heartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill")
                        .foregroundStyle(Theme.pink)
                }
                Label("\(state.todayCount)", systemImage: "waveform")
                    .foregroundStyle(.secondary)
                if state.pendingTransfers > 0 {
                    Label("\(state.pendingTransfers)", systemImage: "arrow.up.circle")
                        .foregroundStyle(Theme.orange)
                }
            }
            .font(.caption2)

            if let error = recorder.lastError {
                Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .onAppear { pulse = true }
        .containerBackground(Theme.pink.gradient.opacity(recorder.isRecording ? 0.35 : 0.15), for: .tabView)
    }
}

struct AskView: View {
    @State private var question = ""

    private var state: WatchState { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ask Auday", systemImage: "sparkles")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.pink)

                TextField("Ask about your day", text: $question)
                    .onSubmit(send)

                if state.isAsking {
                    HStack {
                        ProgressView()
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                } else if let answer = state.answer {
                    Text(answer)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if !state.modelConfigured {
                    Text("Connect an AI model in the iPhone app first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Dictate a question. Your iPhone searches your recordings and answers here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(Theme.violet.gradient.opacity(0.2), for: .tabView)
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        WatchLink.shared.ask(text)
        question = ""
    }
}

struct RecentView: View {
    private var state: WatchState { .shared }

    var body: some View {
        List {
            Section {
                ForEach(state.recent) { chunk in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.time(chunk.startedAt)).font(.system(.body, design: .monospaced))
                            Text(Format.duration(chunk.duration)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: chunk.sent ? "checkmark.icloud" : "arrow.up.circle")
                            .foregroundStyle(chunk.sent ? Theme.mint : Theme.orange)
                    }
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Recordings sync to your iPhone automatically, even later if it's out of range.")
            }
        }
        .overlay {
            if state.recent.isEmpty {
                Text("No recordings yet.").foregroundStyle(.secondary)
            }
        }
        .onAppear { WatchLink.shared.refreshPending() }
    }
}
