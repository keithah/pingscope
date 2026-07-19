import Foundation

public enum WidgetTimelineSchedule {
    public static let refreshInterval: TimeInterval = 10 * 60
    public static let staleInterval: TimeInterval = 15 * 60
    public static let horizon: TimeInterval = 30 * 60

    public static func entryDates(
        now: Date,
        contentGeneratedAt: Date?,
        refreshInterval: TimeInterval = refreshInterval,
        staleInterval: TimeInterval = staleInterval,
        horizon: TimeInterval = horizon
    ) -> [Date] {
        let refreshInterval = max(60, refreshInterval)
        let horizon = max(refreshInterval, horizon)
        let end = now.addingTimeInterval(horizon)
        var dates = Set([now])
        var next = now.addingTimeInterval(refreshInterval)
        while next <= end {
            dates.insert(next)
            next = next.addingTimeInterval(refreshInterval)
        }
        if let contentGeneratedAt {
            let staleDate = contentGeneratedAt.addingTimeInterval(staleInterval)
            if staleDate > now, staleDate <= end {
                dates.insert(staleDate)
            }
        }
        return dates.sorted()
    }

    public static func reloadDate(after entryDates: [Date]) -> Date {
        (entryDates.last ?? Date()).addingTimeInterval(refreshInterval)
    }
}

public enum WidgetRenderFamily: CaseIterable, Sendable {
    case small
    case medium
    case large
}

public struct WidgetFamilyRenderPolicy: Equatable, Sendable {
    public let showsSparkline: Bool
    public let showsStalenessMarker: Bool

    public static func forFamily(_ family: WidgetRenderFamily) -> Self {
        switch family {
        case .small:
            // The compact ring consumes the small family's usable plot area.
            return Self(showsSparkline: false, showsStalenessMarker: true)
        case .medium, .large:
            return Self(showsSparkline: true, showsStalenessMarker: true)
        }
    }
}
