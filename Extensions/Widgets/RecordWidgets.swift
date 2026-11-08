import AppIntents
import Localization
import SwiftUI
import WidgetKit

private let red = Color(red: 0.9, green: 0.28, blue: 0.3)

/// Record from Control Center, the Lock Screen, or the Action Button's list of controls.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.meetlaud.app.record") {
            ControlWidgetButton(action: ToggleRecordingIntent()) {
                Label(L10n.Widgets.record, systemImage: "mic.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: L10n.Widgets.record))
    }
}

private struct StaticEntry: TimelineEntry {
    let date = Date()
    var snapshot: WidgetSnapshot?
}

/// Only what the app wrote. Each change arrives through a reload, so this never wakes up by itself.
private struct SnapshotProvider: TimelineProvider {
    func placeholder(in _: Context) -> StaticEntry {
        StaticEntry()
    }

    func getSnapshot(in _: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

/// One tap to record, on the Home Screen and the Lock Screen.
struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.meetlaud.app.widget.record", provider: SnapshotProvider()) { _ in
            RecordWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(L10n.Widgets.record)
        .description(L10n.Widgets.recordDescription)
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: ToggleRecordingIntent()) {
            switch family {
            case .accessoryCircular:
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .accessoryRectangular:
                Label(L10n.Widgets.record, systemImage: "mic.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(red)
                    Text(L10n.Widgets.record)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Widgets.record)
    }
}

/// Next event and recent meetings. Empty of content unless the person turned that on in Preferences.
struct MeetingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.meetlaud.app.widget.meetings", provider: SnapshotProvider()) { entry in
            MeetingsWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(L10n.Widgets.meetings)
        .description(L10n.Widgets.meetingsDescription)
        .supportedFamilies([.systemMedium])
    }
}

private struct MeetingsWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let event = snapshot?.nextEvent {
                    Text(event.start, style: .time)
                        .font(.caption.bold())
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                ForEach(snapshot?.recent.prefix(3) ?? []) { meeting in
                    if let url = URL(string: "meetlaud://recording/\(meeting.id.uuidString)") {
                        Link(meeting.title, destination: url)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
                if snapshot == nil {
                    Text(L10n.Widgets.contentHidden)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(intent: ToggleRecordingIntent()) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Widgets.record)
        }
    }
}
