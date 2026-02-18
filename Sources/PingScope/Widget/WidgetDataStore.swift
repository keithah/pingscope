import Foundation
import WidgetKit

/// Actor service for writing ping results to widget shared container
actor WidgetDataStore {
    private let shared: UserDefaults
    private let groupIdentifier: String

    init(groupIdentifier: String) {
        self.groupIdentifier = groupIdentifier
        guard let suite = UserDefaults(suiteName: groupIdentifier) else {
            fatalError("Failed to create UserDefaults suite for: \(groupIdentifier)")
        }
        self.shared = suite
    }

    /// Save ping results to shared container and trigger widget reload
    func savePingResults(_ results: [PingResult], hosts: [Host]) async {
        let widgetData = WidgetData(
            results: results.map { result in
                let latencyMS: Double? = result.latency.map { duration in
                    Double(duration.components.seconds) * 1000 +
                    Double(duration.components.attoseconds) / 1_000_000_000_000_000
                }

                return WidgetData.SimplifiedPingResult(
                    hostID: UUID(), // Will match by address in next iteration
                    latencyMS: latencyMS,
                    isSuccess: result.isSuccess,
                    timestamp: result.timestamp
                )
            },
            hosts: hosts.map { host in
                WidgetData.SimplifiedHost(
                    id: host.id,
                    name: host.name,
                    address: host.address
                )
            },
            lastUpdate: Date()
        )

        guard let encoded = try? JSONEncoder().encode(widgetData) else {
            print("Failed to encode widget data")
            return
        }

        shared.set(encoded, forKey: "widgetData")

        // Trigger widget timeline reload
        WidgetCenter.shared.reloadTimelines(ofKind: "PingScopeWidget")
    }
}
