import Foundation
import PingScopeCore

public enum PingScopeIOSAllHostsWidgetSnapshotBuilder {
    public static func make(
        snapshots: [LiveMonitorSessionSnapshot],
        rememberedPrimaryHostID: UUID?,
        recentSamples: [WidgetSample],
        generatedAt: Date,
        isMonitoringActive: Bool
    ) -> WidgetSnapshot {
        let primaryHostID = rememberedPrimaryHostID.flatMap { id in
            snapshots.contains { $0.host.id == id } ? id : nil
        } ?? snapshots.first?.host.id
        let hosts = snapshots.map { entry in
            WidgetHost(
                id: entry.host.id,
                displayName: entry.host.displayName,
                address: entry.host.address,
                method: entry.host.method,
                port: entry.host.port,
                isPrimary: entry.host.id == primaryHostID,
                displayColor: WidgetHostDisplayColor(
                    resolvedColor: ResolvedHostDisplayColor(
                        hostID: entry.host.id,
                        displayColor: entry.host.displayColor
                    )
                )
            )
        }
        let health = snapshots.map { entry in
            WidgetHostHealth(
                hostID: entry.host.id,
                status: entry.health.status,
                latencyMilliseconds: entry.health.latestResult?.latency?.milliseconds,
                consecutiveFailureCount: entry.health.consecutiveFailureCount,
                failureReason: entry.health.latestResult?.failureReason,
                latestResultAt: entry.health.latestResult?.timestamp
            )
        }
        return WidgetSnapshot(
            primaryHostID: primaryHostID,
            hosts: hosts,
            health: health,
            recentSamples: recentSamples,
            networkStatus: .connected,
            generatedAt: generatedAt,
            monitoring: WidgetMonitoringContext(isActive: isMonitoringActive, scope: .allHosts)
        )
    }
}
