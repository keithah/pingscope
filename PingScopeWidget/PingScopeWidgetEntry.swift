import WidgetKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
    let snapshot: WidgetSnapshotData?

    var relevance: TimelineEntryRelevance? {
        if let snapshot {
            let hasIssues = snapshot.health.contains { $0.status == "degraded" || $0.status == "down" || $0.failureReason != nil }
            return TimelineEntryRelevance(
                score: hasIssues ? 100 : 50,
                duration: 15 * 60
            )
        }

        guard let data else { return nil }

        // Higher relevance score for unhealthy hosts (promotes in Smart Stack)
        let hasIssues = data.results.contains { !$0.isSuccess }
        return TimelineEntryRelevance(
            score: hasIssues ? 100 : 50,
            duration: WidgetFreshness.staleInterval
        )
    }

    var isStale: Bool {
        snapshot?.isStale ?? data?.isStale ?? false
    }
}
