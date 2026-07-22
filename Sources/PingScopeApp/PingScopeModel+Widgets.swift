import PingScopeCore
import WidgetKit

extension PingScopeModel {
    func publishWidgetSnapshot(_ snapshot: RuntimeSnapshot) {
        guard widgetsEnabled else { return }
        if widgetSnapshotStore == nil {
            widgetSnapshotStore = WidgetSnapshotStore()
        }
        guard let widgetSnapshotStore else { return }
        let widgetSnapshot = WidgetSnapshot.make(from: snapshot, networkStatus: currentNetworkStatus)
        let previousPublishTask = widgetSnapshotPublishTask
        widgetSnapshotPublishTask = Task { [widgetSnapshotStore, previousPublishTask, weak self] in
            await previousPublishTask?.value
            let publishDecision = await MainActor.run {
                guard let self else {
                    return WidgetSnapshotPublishDecision(
                        shouldSave: false,
                        shouldReloadTimeline: false,
                        shouldReloadControls: false
                    )
                }
                return self.widgetPublishPolicy.decision(
                    for: widgetSnapshot,
                    previousSnapshot: self.lastPublishedWidgetSnapshot,
                    lastTimelineReloadAt: self.lastWidgetTimelineReloadAt
                )
            }
            guard publishDecision.shouldSave else { return }
            guard await widgetSnapshotStore.save(widgetSnapshot) else {
                DebugLog.write("widget snapshot save failed")
                return
            }
            await MainActor.run {
                guard let self else { return }
                if publishDecision.shouldReloadTimeline {
                    self.lastPublishedWidgetSnapshot = widgetSnapshot
                    self.lastWidgetTimelineReloadAt = widgetSnapshot.generatedAt
                    WidgetCenter.shared.reloadAllTimelines()
                } else {
                    self.lastPublishedWidgetSnapshot = widgetSnapshot
                }
            }
        }
    }
}
