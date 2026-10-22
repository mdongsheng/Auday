import SwiftData
import SwiftUI

struct DayTimelineView: View {
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if searchText.isEmpty {
                    DayStrip(selected: $selectedDay)
                        .padding(.vertical, 8)
                }
                RecordingList(day: selectedDay, search: searchText)
            }
            .background(Theme.background)
            .navigationTitle("Timeline")
            .searchable(text: $searchText, prompt: "Search transcripts")
            .navigationDestination(for: Recording.self) { RecordingDetailView(recording: $0) }
        }
    }
}

/// Horizontal strip of the last 30 days.
struct DayStrip: View {
    @Binding var selected: Date

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<30).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                        Button {
                            selected = day
                        } label: {
                            VStack(spacing: 4) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2.weight(.semibold))
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                            }
                            .frame(width: 48, height: 60)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accentGradient)
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(day)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear {
                if let last = days.last { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
    }
}

struct RecordingList: View {
    @Environment(\.modelContext) private var context
    @Query private var recordings: [Recording]
    private let isSearching: Bool

    init(day: Date, search: String) {
        isSearching = !search.isEmpty
        if search.isEmpty {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            _recordings = Query(
                filter: #Predicate<Recording> { $0.startedAt >= day && $0.startedAt < end },
                sort: \Recording.startedAt
            )
        } else {
            _recordings = Query(
                filter: #Predicate<Recording> {
                    $0.transcript.localizedStandardContains(search)
                        || $0.title.localizedStandardContains(search)
                        || $0.summary.localizedStandardContains(search)
                },
                sort: \Recording.startedAt,
                order: .reverse
            )
        }
    }

    var body: some View {
        if recordings.isEmpty {
            ContentUnavailableView(
                isSearching ? LocalizedStringKey("No matches") : LocalizedStringKey("No recordings"),
                systemImage: isSearching ? "magnifyingglass" : "waveform",
                description: Text(isSearching ? LocalizedStringKey("Try another word.") : LocalizedStringKey("Recordings from your Watch and iPhone appear here."))
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(recordings) { recording in
                    NavigationLink(value: recording) {
                        RecordingRow(recording: recording)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(recording)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            recording.isStarred.toggle()
                        } label: {
                            Label("Star", systemImage: "star")
                        }
                        .tint(Theme.orange)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func delete(_ recording: Recording) {
        AudioStorage.delete(recording.fileName)
        context.delete(recording)
        try? context.save()
    }
}
