import SwiftUI
import WidgetKit

struct RecordEntry: TimelineEntry {
    let date: Date
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry { RecordEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: .now)], policy: .never))
    }
}

struct RecordComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecordEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.accentGradient)
                    VStack(alignment: .leading) {
                        Text("Auday").font(Theme.headline)
                        Text("Tap to record").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label("Record with Auday", systemImage: "mic.fill")
            case .accessoryCorner:
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.pink)
                    .widgetLabel("Auday")
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mic.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accentGradient)
                }
            }
        }
        .widgetURL(URL(string: "auday://record"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct RecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecordComplication", provider: RecordProvider()) { entry in
            RecordComplicationView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Start an Auday recording with one tap.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct AudayWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordComplication()
    }
}
