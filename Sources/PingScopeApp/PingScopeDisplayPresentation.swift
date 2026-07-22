import Foundation
import PingScopeCore
#if DEBUG
import os

private let displayPresentationPointsOfInterestLog = OSLog(
    subsystem: "tv.kodi.pingscope",
    category: .pointsOfInterest
)
#endif

struct PingScopeDisplayPreparation {
    let visibleHistorySamples: [PingResult]
    let visibleSamples: [PingResult]
    let allHostGraphSeries: [HostLatencyGraphSeries]

    init(
        visibleHistorySamples: [PingResult],
        visibleSamples: [PingResult],
        allHostGraphSeries: [HostLatencyGraphSeries]
    ) {
        self.visibleHistorySamples = visibleHistorySamples
        self.visibleSamples = visibleSamples
        self.allHostGraphSeries = allHostGraphSeries
    }

    init(
        snapshot: RuntimeSnapshot,
        selectedRange: TimeRange,
        visibleHistorySamples: [PingResult],
        includesAllHosts: Bool,
        presenter: DisplayStatePresenter,
        now: Date
    ) {
        let liveSamples = presenter.visibleSamples(in: snapshot.primarySeries, range: selectedRange, now: now)
        self.visibleHistorySamples = visibleHistorySamples
        self.visibleSamples = presenter.mergedSamples(
            history: visibleHistorySamples,
            live: liveSamples,
            range: selectedRange,
            now: now
        )
        self.allHostGraphSeries = includesAllHosts
            ? Self.makeAllHostGraphSeries(snapshot: snapshot, selectedRange: selectedRange, now: now)
            : []
    }

    private static func makeAllHostGraphSeries(
        snapshot: RuntimeSnapshot,
        selectedRange: TimeRange,
        now: Date
    ) -> [HostLatencyGraphSeries] {
        let cutoff = now.addingTimeInterval(-selectedRange.duration)
        let primaryHostID = snapshot.primaryHost?.id
        return snapshot.hosts.compactMap { host in
            guard host.isEnabled else { return nil }
            let samples = snapshot.samplesByHost[host.id]?.samples(since: cutoff) ?? []
            return HostLatencyGraphSeries(
                host: host,
                samples: samples,
                isPrimary: host.id == primaryHostID
            )
        }
    }
}

struct PingScopeDisplayPresentation {
    let visibleHistorySamples: [PingResult]
    let visibleSamples: [PingResult]
    let allHostGraphSeries: [HostLatencyGraphSeries]
    let hostStatusSummaries: [HostStatusSummary]
    let primaryGraphData: LatencyGraphData
    let allHostsGraphData: MultiHostLatencyGraphData
    let primaryStats: SampleStats
    let latestStarlinkTelemetry: StarlinkTelemetry?
    let recentVisibleSamples: [PingResult]
    let focusedIdentityColor: ResolvedHostDisplayColor?
    let focusedGraphColor: ResolvedHostDisplayColor?
    let focusedRingColor: ResolvedHostDisplayColor?

    init() {
        self.visibleHistorySamples = []
        self.visibleSamples = []
        self.allHostGraphSeries = []
        self.hostStatusSummaries = []
        self.primaryGraphData = LatencyGraphData(samples: [])
        self.allHostsGraphData = MultiHostLatencyGraphData(series: [])
        self.primaryStats = SampleStats(samples: [])
        self.latestStarlinkTelemetry = nil
        self.recentVisibleSamples = []
        self.focusedIdentityColor = nil
        self.focusedGraphColor = nil
        self.focusedRingColor = nil
    }

    init(
        snapshot: RuntimeSnapshot,
        selectedRange: TimeRange,
        visibleHistorySamples: [PingResult],
        includesAllHosts: Bool,
        presenter: DisplayStatePresenter,
        now: Date = Date()
    ) {
        self.init(
            snapshot: snapshot,
            preparation: PingScopeDisplayPreparation(
                snapshot: snapshot,
                selectedRange: selectedRange,
                visibleHistorySamples: visibleHistorySamples,
                includesAllHosts: includesAllHosts,
                presenter: presenter,
                now: now
            ),
            includesAllHosts: includesAllHosts,
            presenter: presenter
        )
    }

    init(
        snapshot: RuntimeSnapshot,
        preparation: PingScopeDisplayPreparation,
        includesAllHosts: Bool,
        presenter: DisplayStatePresenter
    ) {
        #if DEBUG
        let signpostID = OSSignpostID(log: displayPresentationPointsOfInterestLog)
        os_signpost(
            .begin,
            log: displayPresentationPointsOfInterestLog,
            name: "PingScopeDisplayPresentation.init",
            signpostID: signpostID
        )
        defer {
            os_signpost(
                .end,
                log: displayPresentationPointsOfInterestLog,
                name: "PingScopeDisplayPresentation.init",
                signpostID: signpostID
            )
        }
        #endif
        self.visibleHistorySamples = preparation.visibleHistorySamples
        self.visibleSamples = preparation.visibleSamples
        self.allHostGraphSeries = preparation.allHostGraphSeries
        self.hostStatusSummaries = presenter.hostStatusSummaries(in: snapshot)
        self.primaryGraphData = LatencyGraphData(samples: preparation.visibleSamples)
        self.allHostsGraphData = MultiHostLatencyGraphData(series: preparation.allHostGraphSeries)
        self.primaryStats = SampleStats(samples: preparation.visibleSamples)
        self.latestStarlinkTelemetry = Self.latestStarlinkTelemetry(
            in: preparation.visibleSamples,
            primaryHost: snapshot.primaryHost,
            includesAllHosts: includesAllHosts
        )
        self.recentVisibleSamples = Array(preparation.visibleSamples.suffix(8).reversed())
        let focusedIdentityColor = snapshot.primaryHost.map {
            ResolvedHostDisplayColor(hostID: $0.id, displayColor: $0.displayColor)
        }
        self.focusedIdentityColor = focusedIdentityColor
        self.focusedGraphColor = focusedIdentityColor
        self.focusedRingColor = focusedIdentityColor
    }

    private static func latestStarlinkTelemetry(
        in visibleSamples: [PingResult],
        primaryHost: HostConfig?,
        includesAllHosts: Bool
    ) -> StarlinkTelemetry? {
        guard !includesAllHosts,
              primaryHost?.method == .starlink else {
            return nil
        }
        return visibleSamples.reversed().lazy.compactMap(\.metadata.starlink).first
    }

}
