import SwiftUI

/// Big gradient record button with a live level ring, used on the Today screen.
struct RecordCard: View {
    private var recorder: PhoneRecorder { .shared }
    private var queue: ProcessingQueue { .shared }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Button {
                    Task { await recorder.toggle() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Theme.pink.opacity(0.35), lineWidth: 6)
                            .scaleEffect(recorder.isRecording ? 1 + CGFloat(recorder.level) * 0.35 : 1)
                            .animation(.easeOut(duration: 0.1), value: recorder.level)
                        Circle()
                            .fill(Theme.accentGradient)
                            .padding(8)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 84, height: 84)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: recorder.isRecording)

                VStack(alignment: .leading, spacing: 4) {
                    if recorder.isRecording, let start = recorder.sessionStart {
                        Text("Recording")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.pink)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Format.clock(context.date.timeIntervalSince(start)))
                                .font(.system(.title, design: .monospaced).weight(.semibold))
                        }
                    } else {
                        Text("Tap to record")
                            .font(Theme.headline)
                        Text("Or start from your Apple Watch.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if queue.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Processing \(queue.currentTitle ?? "")…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let error = recorder.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: 18)
    }
}

/// Starts and stops recording on the paired Apple Watch, mirroring its live state.
struct WatchRecordCard: View {
    private var remote: WatchRemote { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                GradientIcon(
                    systemName: "applewatch",
                    size: 44,
                    gradient: remote.isRecording ? Theme.accentGradient : Theme.calmGradient
                )

                VStack(alignment: .leading, spacing: 2) {
                    if remote.isRecording {
                        Text("Recording on Apple Watch")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.pink)
                        HStack(spacing: 10) {
                            if let start = remote.sessionStart {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(Format.clock(context.date.timeIntervalSince(start)))
                                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                }
                            }
                            if let bpm = remote.heartRate {
                                Label("\(Int(bpm))", systemImage: "heart.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.pink)
                            }
                        }
                    } else if remote.isBusy {
                        Text("Starting on Watch…")
                            .font(Theme.headline)
                    } else {
                        Text("Record on Apple Watch")
                            .font(Theme.headline)
                        Text("The Watch starts recording, even with its app closed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)

                if remote.isBusy {
                    ProgressView()
                } else {
                    Button {
                        if remote.isRecording {
                            remote.stop()
                        } else {
                            Task { await remote.start() }
                        }
                    } label: {
                        Text(remote.isRecording ? LocalizedStringKey("Stop") : LocalizedStringKey("Start"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact, trigger: remote.isRecording)
                }
            }

            if let error = remote.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .card(padding: 16)
        .onAppear { remote.refreshAvailability() }
    }
}

struct StatTile: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let unit: String
    var gradient: LinearGradient = Theme.accentGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GradientIcon(systemName: icon, size: 28, gradient: gradient)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
    }
}

struct Badge: View {
    let icon: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

/// A recording card with a time rail, used in Today and Timeline.
struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(Format.time(recording.startedAt))
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recording.displayTitle)
                        .font(Theme.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if recording.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(Theme.orange).font(.caption)
                    }
                }
                if !recording.summary.isEmpty {
                    Text(recording.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !recording.transcript.isEmpty {
                    Text(recording.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                FlowBadges(recording: recording)
            }
            .card(padding: 14)
        }
    }
}

struct FlowBadges: View {
    let recording: Recording

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Badge(icon: recording.source == .watch ? "applewatch" : "iphone", text: Format.duration(recording.duration))
                if let place = recording.placeName {
                    Badge(icon: "mappin", text: place, tint: Theme.sky)
                }
                if let hr = recording.avgHeartRate {
                    Badge(icon: "heart.fill", text: "\(Int(hr))", tint: Theme.pink)
                }
                if let stress = recording.stressLevel {
                    Badge(icon: "brain.head.profile", text: "\(Int(stress))", tint: Theme.violet)
                }
                StatusBadge(status: recording.status, hasError: recording.errorMessage != nil)
            }
        }
    }
}

struct StatusBadge: View {
    let status: RecordingStatus
    var hasError = false

    var body: some View {
        switch status {
        case .pending:
            Badge(icon: "clock", text: String(localized: "Queued"))
        case .transcribing:
            Badge(icon: "text.bubble", text: String(localized: "Transcribing"), tint: Theme.orange)
        case .summarizing:
            Badge(icon: "sparkles", text: String(localized: "Summarizing"), tint: Theme.orange)
        case .failed:
            Badge(icon: "exclamationmark.triangle", text: String(localized: "Failed"), tint: .red)
        case .transcribed, .done:
            if hasError {
                Badge(icon: "exclamationmark.circle", text: String(localized: "No summary"), tint: .yellow)
            }
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(Theme.pink) }
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
        }
        .padding(.top, 8)
    }
}

/// Renders model Markdown (bold, italics, lists as plain lines) while preserving line breaks.
struct MarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}
