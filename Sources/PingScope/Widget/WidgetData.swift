import Foundation

/// Simplified widget data model for sharing via UserDefaults
struct WidgetData: Codable, Equatable, Sendable {
    let version: Int = 1
    let results: [SimplifiedPingResult]
    let hosts: [SimplifiedHost]
    let lastUpdate: Date

    struct SimplifiedPingResult: Codable, Equatable, Sendable {
        let hostID: UUID
        let latencyMS: Double?
        let isSuccess: Bool
        let timestamp: Date
    }

    struct SimplifiedHost: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let address: String
    }

    static let placeholder = WidgetData(
        results: [],
        hosts: [],
        lastUpdate: Date()
    )

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 15 * 60
    }
}
