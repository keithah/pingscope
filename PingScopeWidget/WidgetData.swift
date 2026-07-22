import Foundation
import PingScopeExtensionSupport

enum WidgetFreshness {
    static let staleInterval = WidgetTimelineSchedule.staleInterval
}

struct WidgetData: Codable, Equatable, Sendable {
    var version: Int
    var results: [SimplifiedPingResult]
    var hosts: [SimplifiedHost]
    var lastUpdate: Date

    init(
        version: Int = 1,
        results: [SimplifiedPingResult],
        hosts: [SimplifiedHost],
        lastUpdate: Date
    ) {
        self.version = version
        self.results = results
        self.hosts = hosts
        self.lastUpdate = lastUpdate
    }

    struct SimplifiedPingResult: Codable, Equatable, Sendable {
        var hostID: UUID
        var latencyMS: Double?
        var isSuccess: Bool
        var timestamp: Date
    }

    struct SimplifiedHost: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var address: String
    }

    static let placeholder = WidgetData(
        results: [],
        hosts: [],
        lastUpdate: Date()
    )

    var isStale: Bool {
        isStale(at: Date())
    }

    func isStale(at date: Date) -> Bool {
        WidgetContentFreshness.isStale(contentGeneratedAt: lastUpdate, at: date)
    }
}
