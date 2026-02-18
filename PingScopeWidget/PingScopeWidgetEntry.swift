import WidgetKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?

    var relevance: TimelineEntryRelevance? {
        guard let data = data else { return nil }

        // Higher relevance score for unhealthy hosts (promotes in Smart Stack)
        let hasIssues = data.results.contains { !$0.isSuccess }
        return TimelineEntryRelevance(
            score: hasIssues ? 100 : 50,
            duration: 15 * 60  // 15 minutes
        )
    }
}
