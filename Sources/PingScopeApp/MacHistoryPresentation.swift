import Foundation
import PingScopeCore
import PingScopeHistoryKit

struct MacHistoryNetworkTablePresentation: Equatable, Sendable {
    let rows: [HistoryNetworkCardPresentation]

    nonisolated init(samples: [PingResult]) {
        rows = HistoryNetworkPresentation(samples: samples).cards
    }
}

struct MacHistorySurfacePresentation: Equatable, Sendable {
    let hostID: UUID
    let range: HistoryRange
    let cutoff: Date
    let endingAt: Date
    let samples: [PingResult]
    let chartReduction: HistoryChartReduction
    let metrics: HistoryMetrics
    let sessions: [HistorySession]
    let mapPresentation: HistoryMapPresentation
    let networkTable: MacHistoryNetworkTablePresentation
    let incidentLog: HistoryIncidentLog
    let weeklyDigest: HistoryWeeklyDigest?
    let isCollecting: Bool

    nonisolated init(
        loadResult: PingScopeIOSHistoryLoadResult,
        host: HostConfig? = nil,
        weeklyDigest: HistoryWeeklyDigest? = nil
    ) {
        hostID = loadResult.hostID
        range = loadResult.range
        cutoff = loadResult.cutoff
        endingAt = loadResult.endingAt
        samples = loadResult.samples
        chartReduction = loadResult.chartReduction
        metrics = HistoryMetrics(samples: loadResult.samples)
        sessions = HistorySession.sessionize(loadResult.samples)
        mapPresentation = HistoryMapPresentation(samples: loadResult.samples)
        networkTable = MacHistoryNetworkTablePresentation(samples: loadResult.samples)
        incidentLog = HistoryIncidentLog(samples: loadResult.samples, endingAt: loadResult.endingAt)
        self.weeklyDigest = weeklyDigest ?? host.flatMap {
            HistoryWeeklyDigest.make(
                hosts: [$0],
                samplesByHost: [$0.id: loadResult.samples],
                endingAt: loadResult.endingAt
            )
        }
        isCollecting = loadResult.isCollecting
    }
}

struct MacHistoryReportPresentation: Equatable, Sendable, Identifiable {
    let content: HistoryReportPresentation

    nonisolated var id: String {
        "\(content.hostName)|\(content.rangeLabel)|\(content.sampleCount)"
    }

    nonisolated static func make(
        host: HostConfig?,
        surface: MacHistorySurfacePresentation?
    ) -> MacHistoryReportPresentation? {
        guard let host, let surface, host.id == surface.hostID, !surface.samples.isEmpty else {
            return nil
        }
        return MacHistoryReportPresentation(content: HistoryReportPresentation(
            host: host,
            range: surface.range,
            samples: surface.samples,
            mapSummary: surface.mapPresentation.summary
        ))
    }

    nonisolated static func isActionEnabled(
        isLoading: Bool,
        surface: MacHistorySurfacePresentation?
    ) -> Bool {
        !isLoading && !(surface?.samples.isEmpty ?? true)
    }
}

struct MacHistoryLoadingPresentation {
    nonisolated static func showsToolbarSpinner(
        isLoading: Bool,
        surface: MacHistorySurfacePresentation?
    ) -> Bool {
        isLoading && surface == nil
    }
}

protocol MacHistorySurfaceLoading: Sendable {
    func load(
        store: any PingHistoryStore,
        hostID: UUID,
        range: HistoryRange,
        host: HostConfig?,
        allHosts: [HostConfig],
        now: Date
    ) async -> MacHistorySurfacePresentation?
}

actor MacHistorySurfaceLoader: MacHistorySurfaceLoading {
    private let loader = PingScopeIOSHistoryLoader()
    private let weeklyDigestLoader = HistoryWeeklyDigestLoader()

    func load(
        store: any PingHistoryStore,
        hostID: UUID,
        range: HistoryRange,
        host: HostConfig? = nil,
        allHosts: [HostConfig] = [],
        now: Date = Date()
    ) async -> MacHistorySurfacePresentation? {
        guard let result = await loader.load(store: store, hostID: hostID, range: range, now: now) else {
            return nil
        }
        let digest = await weeklyDigestLoader.load(
            store: store,
            hosts: allHosts,
            endingAt: now
        )
        return MacHistorySurfacePresentation(loadResult: result, host: host, weeklyDigest: digest)
    }
}

struct MacHistoryWindowLoadLifecycle {
    private var hasAppeared = false

    mutating func consumeFirstAppearance() -> Bool {
        guard !hasAppeared else { return false }
        hasAppeared = true
        return true
    }
}

extension PingScopeModel {
    var historySurfaceRefreshKey: String {
        "\(historySurfaceHostID?.uuidString ?? "none")|\(historySurfaceRange.rawValue)"
    }

    var historySurfaceHost: HostConfig? {
        guard let historySurfaceHostID else { return configuredPrimaryHost ?? configuredHosts.first }
        return configuredHosts.first { $0.id == historySurfaceHostID } ?? configuredPrimaryHost ?? configuredHosts.first
    }

    func prepareHistorySurface() {
        if historySurfaceHostID == nil || !configuredHosts.contains(where: { $0.id == historySurfaceHostID }) {
            historySurfaceHostID = configuredPrimaryHost?.id ?? configuredHosts.first?.id
        }
        refreshHistorySurface()
    }

    func refreshHistorySurface() {
        historySurfaceTask?.cancel()
        historySurfaceLoadToken += 1
        let loadToken = historySurfaceLoadToken
        guard let store = historySurfaceStore, let hostID = historySurfaceHost?.id else {
            historySurfacePresentation = nil
            isLoadingHistorySurface = false
            return
        }
        let range = historySurfaceRange
        let host = historySurfaceHost
        let allHosts = configuredHosts
        isLoadingHistorySurface = true
        historySurfaceTask = Task { [weak self, historySurfaceLoader] in
            let loaded = await historySurfaceLoader.load(
                store: store,
                hostID: hostID,
                range: range,
                host: host,
                allHosts: allHosts,
                now: Date()
            )
            guard let self, historySurfaceLoadToken == loadToken else { return }
            if !Task.isCancelled,
               historySurfaceHost?.id == hostID,
               historySurfaceRange == range,
               let loaded {
                historySurfacePresentation = loaded
            }
            isLoadingHistorySurface = false
        }
    }
}
