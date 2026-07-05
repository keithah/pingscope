import Foundation
import PingScopeCore

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
    }

    init(
        snapshot: RuntimeSnapshot,
        selectedRange: TimeRange,
        visibleHistorySamples: [PingResult],
        includesAllHosts: Bool,
        presenter: DisplayStatePresenter,
        now: Date = Date()
    ) {
        let liveSamples = presenter.visibleSamples(in: snapshot.primarySeries, range: selectedRange, now: now)
        let visibleSamples = presenter.mergedSamples(
            history: visibleHistorySamples,
            live: liveSamples,
            range: selectedRange,
            now: now
        )
        let allHostGraphSeries = includesAllHosts
            ? Self.makeAllHostGraphSeries(snapshot: snapshot, selectedRange: selectedRange, now: now)
            : []

        self.visibleHistorySamples = visibleHistorySamples
        self.visibleSamples = visibleSamples
        self.allHostGraphSeries = allHostGraphSeries
        self.hostStatusSummaries = presenter.hostStatusSummaries(in: snapshot)
        self.primaryGraphData = LatencyGraphData(samples: visibleSamples)
        self.allHostsGraphData = MultiHostLatencyGraphData(series: allHostGraphSeries)
        self.primaryStats = SampleStats(samples: visibleSamples)
        self.latestStarlinkTelemetry = Self.latestStarlinkTelemetry(
            in: visibleSamples,
            primaryHost: snapshot.primaryHost,
            includesAllHosts: includesAllHosts
        )
        self.recentVisibleSamples = Array(visibleSamples.suffix(8).reversed())
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

    private static func makeAllHostGraphSeries(
        snapshot: RuntimeSnapshot,
        selectedRange: TimeRange,
        now: Date
    ) -> [HostLatencyGraphSeries] {
        let cutoff = now.addingTimeInterval(-selectedRange.duration)
        let primaryHostID = snapshot.primaryHost?.id
        return snapshot.hosts.enumerated().compactMap { index, host in
            guard host.isEnabled else { return nil }
            let samples = snapshot.samplesByHost[host.id]?.samples(since: cutoff) ?? []
            return HostLatencyGraphSeries(
                host: host,
                samples: samples,
                color: HostLatencyGraphSeries.palette[index % HostLatencyGraphSeries.palette.count],
                isPrimary: host.id == primaryHostID
            )
        }
    }
}
