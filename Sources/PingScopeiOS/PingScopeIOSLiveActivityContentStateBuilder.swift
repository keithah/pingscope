import Foundation
import PingScopeCore

public enum PingScopeIOSLiveActivityContentStateBuilder {
    public static func focused(
        host: HostConfig,
        session: MonitorSessionState,
        health: HostHealth,
        samples: [PingResult],
        showsDynamicIslandDetails: Bool = true,
        at date: Date = Date()
    ) -> PingScopeLiveActivityAttributes.ContentState {
        let latestResult = session.latestResult ?? health.latestResult
        let isStale = session.phase(at: date) != .live
        let row = PingScopeLiveActivityHostRow(
            snapshot: PingScopeIOSHostRowSnapshot(
                host: host,
                health: health,
                samples: samples,
                isStale: isStale
            )
        )

        return PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: latestResult?.latency.map { Int($0.milliseconds.rounded()) },
            status: health.status,
            lastUpdatedAt: latestResult?.timestamp,
            remainingSeconds: session.duration == .continuous
                ? 0
                : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
            isStale: isStale,
            failureMessage: latestResult?.failureReason?.userMessage,
            mode: .focused,
            hostRows: [row],
            showsDynamicIslandDetails: showsDynamicIslandDetails
        )
    }
}
