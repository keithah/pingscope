import WidgetKit
import SwiftUI

@main
struct PingScopeWidget: Widget {
    let kind: String = "PingScopeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PingScopeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("PingScope")
        .description("Monitor ping status and latency")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
