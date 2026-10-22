import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Query private var recordings: [Recording]
    @Query private var reflections: [DayReflection]
    @State private var health = HealthSnapshot()
    @State private var isGenerating = false
    @State private var reflectionError: String?

    private let day: Date

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        day = start
        _recordings = Query(
            filter: #Predicate<Recording> { $0.startedAt >= start && $0.startedAt < end },
            sort: \Recording.startedAt,
            order: .reverse
        )
        _reflections = Query(filter: #Predicate<DayReflection> { $0.day == start })
    }

    private var models: ModelSettings { .shared }

    private var highlights: [Highlight] {
        recordings.flatMap(\.highlights).sorted { $0.date > $1.date }
    }

    private var totalDuration: TimeInterval {
        recordings.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    RecordCard()
                    reflectionCard
                    statsGrid
                    if !health.heartRateSeries.isEmpty { heartRateCard }
                    if !highlights.isEmpty { highlightsSection }
                    recentSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationDestination(for: Recording.self) { RecordingDetailView(recording: $0) }
            .refreshable { await loadHealth() }
            .task { await loadHealth() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(Theme.display())
            Text("\(recordings.count) recordings · \(Format.duration(totalDuration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Reflection

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GradientIcon(systemName: "sparkles", size: 28, gradient: Theme.calmGradient)
                Text("Daily Reflection").font(Theme.headline)
                Spacer()
                if isGenerating {
                    ProgressView()
                } else if models.isConfigured {
                    Button(reflections.first == nil ? LocalizedStringKey("Generate") : LocalizedStringKey("Refresh")) {
                        Task { await generateReflection() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if let reflection = reflections.first {
                MarkdownText(text: reflection.content)
                    .font(.callout)
                Text("Updated \(Format.time(reflection.generatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if models.isConfigured {
                Text("Generate a reflection of your day from your recordings, places and health data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect an AI model in Settings to get summaries, daily reflections and chat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let reflectionError {
                Text(reflectionError).font(.footnote).foregroundStyle(.red)
            }
        }
        .card(padding: 18)
    }

    private func generateReflection() async {
        isGenerating = true
        reflectionError = nil
        do {
            _ = try await ReflectionGenerator.generate(for: day)
        } catch {
            reflectionError = error.localizedDescription
        }
        isGenerating = false
    }

    // MARK: Health

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(icon: "heart.fill", title: "Heart Rate", value: health.averageHeartRate.map { "\(Int($0))" } ?? "–", unit: "bpm")
            StatTile(
                icon: "brain.head.profile",
                title: "Stress",
                value: health.stress.map { "\(Int($0))" } ?? "–",
                unit: "/100",
                gradient: Theme.calmGradient
            )
            StatTile(
                icon: "figure.walk",
                title: "Steps",
                value: health.steps.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–",
                unit: "",
                gradient: LinearGradient(colors: [Theme.mint, Theme.sky], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            StatTile(
                icon: "bed.double.fill",
                title: "Sleep",
                value: health.sleepHours.map { String(format: "%.1f", $0) } ?? "–",
                unit: "h",
                gradient: LinearGradient(colors: [Theme.sky, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart rate today").font(Theme.headline)
                Spacer()
                if let min = health.minHeartRate, let max = health.maxHeartRate {
                    Text("\(Int(min))–\(Int(max)) bpm").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(health.heartRateSeries) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("BPM", point.bpm))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.pink.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                        )
                    LineMark(x: .value("Time", point.date), y: .value("BPM", point.bpm))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accentGradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                ForEach(recordings) { recording in
                    RuleMark(x: .value("Recording", recording.startedAt))
                        .foregroundStyle(Theme.violet.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 150)
        }
        .card(padding: 18)
    }

    private func loadHealth() async {
        health = await HealthStore.shared.snapshot(for: day)
    }

    // MARK: Lists

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Highlights", icon: "star.fill")
            ForEach(highlights.prefix(6)) { highlight in
                HStack(alignment: .top, spacing: 10) {
                    Capsule().fill(Theme.accentGradient).frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.text).font(.callout)
                        Text(Format.time(highlight.date)).font(Theme.mono).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today's recordings", icon: "waveform")
            if recordings.isEmpty {
                Text("Nothing recorded yet today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .card()
            }
            ForEach(recordings.prefix(5)) { recording in
                NavigationLink(value: recording) {
                    RecordingRow(recording: recording)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
