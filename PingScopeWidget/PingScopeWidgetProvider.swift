import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    private let groupIdentifier = "6R7S5GA944.group.com.hadm.PingScope"  // Use same from Plan 01

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let entry = WidgetEntry(date: Date(), data: loadData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let data = loadData()
        let entry = WidgetEntry(date: Date(), data: data)

        // Next update in 10 minutes (respects 40-70/day budget)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadData() -> WidgetData? {
        guard let shared = UserDefaults(suiteName: groupIdentifier),
              let data = shared.data(forKey: "widgetData"),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return nil
        }
        return decoded
    }
}
