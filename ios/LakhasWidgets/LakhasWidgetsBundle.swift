import LakhasKit
import SwiftUI
import WidgetKit

@main
struct LakhasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ProbeWidget()
    }
}

/// Phase 1 probe widget: proves whether the widget and the app share a container on a
/// sideloaded install (docs/sideloading.md §4). The real widgets arrive in Phase 9.
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LakhasProbe", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.probe.name")
        .description("widget.probe.description")
        .supportedFamilies([.systemSmall])
    }
}

struct ProbeEntry: TimelineEntry {
    let date: Date
    let isShared: Bool
    let appSeen: Date?
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, isShared: true, appSeen: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
    }

    private func makeEntry() -> ProbeEntry {
        let location = AppGroupResolver.resolve()
        let store = HeartbeatStore(location: location)
        try? store.write(Heartbeat(
            role: .widget,
            date: .now,
            bundleID: Bundle.main.bundleIdentifier ?? "",
            appGroupID: location.appGroupID
        ))
        return ProbeEntry(date: .now, isShared: location.isShared, appSeen: store.read(.app)?.date)
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("widget.probe.title")
                .font(.headline)
                .foregroundStyle(Theme.Palette.primary)
            Spacer(minLength: 0)
            if !entry.isShared {
                Text("widget.probe.noGroup")
                    .font(.footnote)
            } else if let appSeen = entry.appSeen {
                Text("widget.probe.appSeen")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.muted)
                Text(appSeen, style: .relative)
                    .font(.footnote.monospacedDigit())
            } else {
                Text("widget.probe.openApp")
                    .font(.footnote)
            }
        }
        .foregroundStyle(Theme.Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Theme.Palette.surface, for: .widget)
    }
}
