import Foundation

public enum WidgetTimelineSchedule {
    public static let refreshInterval: TimeInterval = 10 * 60
    // WidgetKit commonly budgets refreshes across a 15–60 minute window. Keep
    // the deadline bounded without marking a live snapshot stale before the
    // system has had a normal opportunity to honor the app's reload request.
    public static let staleInterval: TimeInterval = 60 * 60
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

public enum WidgetContentFreshness {
    public static let staleInterval = WidgetTimelineSchedule.staleInterval

    public static func isStale(contentGeneratedAt: Date?, at date: Date) -> Bool {
        guard let contentGeneratedAt else { return false }
        return date.timeIntervalSince(contentGeneratedAt) >= staleInterval
    }
}

public struct WidgetTimelineEntryMapping: Equatable, Sendable {
    public let date: Date
    public let isStale: Bool

    public init(date: Date, isStale: Bool) {
        self.date = date
        self.isStale = isStale
    }
}

public enum WidgetTimelineEntryMapper {
    public static func entries(
        now: Date,
        contentGeneratedAt: Date?
    ) -> [WidgetTimelineEntryMapping] {
        WidgetTimelineSchedule.entryDates(
            now: now,
            contentGeneratedAt: contentGeneratedAt
        ).map { date in
            WidgetTimelineEntryMapping(
                date: date,
                isStale: WidgetContentFreshness.isStale(
                    contentGeneratedAt: contentGeneratedAt,
                    at: date
                )
            )
        }
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
