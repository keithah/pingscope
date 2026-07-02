import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    private let groupIdentifier = "6R7S5GA944.group.com.hadm.PingScope"  // Use same from Plan 01

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), data: .placeholder, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let entry = WidgetEntry(date: Date(), data: loadLegacyData(), snapshot: loadSnapshotData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), data: loadLegacyData(), snapshot: loadSnapshotData())

        // Next update in 10 minutes (respects 40-70/day budget)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
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
