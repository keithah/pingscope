import Foundation

public struct WidgetSnapshotPublishDecision: Equatable, Sendable {
    public let shouldSave: Bool
    public let shouldReloadTimeline: Bool

    public init(shouldSave: Bool, shouldReloadTimeline: Bool) {
        self.shouldSave = shouldSave
        self.shouldReloadTimeline = shouldReloadTimeline
    }
}

public struct WidgetSnapshotPublishPolicy: Sendable {
    public var heartbeatInterval: TimeInterval
    public var timelineReloadInterval: TimeInterval

    public init(heartbeatInterval: TimeInterval = 5 * 60, timelineReloadInterval: TimeInterval = 5 * 60) {
        self.heartbeatInterval = heartbeatInterval
        self.timelineReloadInterval = timelineReloadInterval
    }

    public func decision(
        for snapshot: WidgetSnapshot,
        previousSnapshot: WidgetSnapshot?,
        lastTimelineReloadAt: Date?
    ) -> WidgetSnapshotPublishDecision {
        let widgetStateChanged = !snapshot.hasSameWidgetState(as: previousSnapshot)
        let sampleFeedChanged = !snapshot.hasSameContent(as: previousSnapshot)
        let heartbeatDue = snapshot.generatedAt.timeIntervalSince(previousSnapshot?.generatedAt ?? .distantPast) >= heartbeatInterval
        let sampleFeedSaveDue = sampleFeedChanged
            && snapshot.generatedAt.timeIntervalSince(lastTimelineReloadAt ?? .distantPast) >= timelineReloadInterval
        guard widgetStateChanged || heartbeatDue || sampleFeedSaveDue else {
            return WidgetSnapshotPublishDecision(shouldSave: false, shouldReloadTimeline: false)
        }

        return WidgetSnapshotPublishDecision(
            shouldSave: true,
            shouldReloadTimeline: shouldReloadTimeline(
                for: snapshot,
                previousSnapshot: previousSnapshot,
                lastTimelineReloadAt: lastTimelineReloadAt,
                widgetStateChanged: widgetStateChanged,
                sampleFeedChanged: sampleFeedChanged
            )
        )
    }

    private func shouldReloadTimeline(
        for snapshot: WidgetSnapshot,
        previousSnapshot: WidgetSnapshot?,
        lastTimelineReloadAt: Date?,
        widgetStateChanged: Bool,
        sampleFeedChanged: Bool
    ) -> Bool {
        guard sampleFeedChanged else { return false }
        guard previousSnapshot != nil else { return true }
        if widgetStateChanged {
            return true
        }
        return snapshot.generatedAt.timeIntervalSince(lastTimelineReloadAt ?? .distantPast) >= timelineReloadInterval
    }
}
