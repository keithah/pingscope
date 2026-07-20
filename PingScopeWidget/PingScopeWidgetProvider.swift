import WidgetKit
import SwiftUI
import PingScopeExtensionSupport

struct Provider: TimelineProvider {
    // Must match WidgetSnapshotStore.defaultSuiteName in PingScopeCore (the
    // widget does not link the package). macOS uses the classic team-prefixed
    // app-group form; iOS provisioning only accepts group.-prefixed IDs.
    #if os(macOS)
    private let groupIdentifier = "6R7S5GA944.group.com.hadm.PingScope"
    #else
    private let groupIdentifier = "group.com.hadm.pingscope"
    #endif

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), data: .placeholder, snapshot: nil, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshotData()
        let legacyData = snapshot == nil ? loadLegacyData() : nil
        let entryMappings = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: snapshot?.generatedAt ?? legacyData?.lastUpdate
        )
        let entries = entryMappings.map {
            WidgetEntry(date: $0.date, data: legacyData, snapshot: snapshot, isStale: $0.isStale)
        }
        let timeline = Timeline(
            entries: entries,
            policy: .after(WidgetTimelineSchedule.reloadDate(after: entryMappings.map(\.date)))
        )

        completion(timeline)
    }

    private func makeEntry(date: Date = Date()) -> WidgetEntry {
        let snapshot = loadSnapshotData()
        let legacyData = snapshot == nil ? loadLegacyData() : nil
        return WidgetEntry(
            date: date,
            data: legacyData,
            snapshot: snapshot,
            isStale: snapshot?.isStale(at: date) ?? legacyData?.isStale(at: date) ?? false
        )
    }

    private func loadSnapshotData() -> WidgetSnapshotData? {
        guard let shared = UserDefaults(suiteName: groupIdentifier),
              let data = shared.data(forKey: "PingScopeWidgetSnapshot"),
              let decoded = try? JSONDecoder.widgetDecoder.decode(WidgetSnapshotData.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func loadLegacyData() -> WidgetData? {
        // The app writes this blob with the same ISO-8601 encoder as the primary
        // snapshot (WidgetSnapshotStore.save). A default-strategy decoder would
        // always throw on the Date fields, silently killing the fallback path.
        guard let shared = UserDefaults(suiteName: groupIdentifier),
              let data = shared.data(forKey: "widgetData"),
              let decoded = try? JSONDecoder.widgetDecoder.decode(WidgetData.self, from: data) else {
            return nil
        }
        return decoded
    }
}

private extension JSONDecoder {
    static var widgetDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
