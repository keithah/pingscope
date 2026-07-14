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
    let networkTable: MacHistoryNetworkTablePresentation
    let isCollecting: Bool

    nonisolated init(loadResult: PingScopeIOSHistoryLoadResult) {
        hostID = loadResult.hostID
        range = loadResult.range
        cutoff = loadResult.cutoff
        endingAt = loadResult.endingAt
        samples = loadResult.samples
        chartReduction = loadResult.chartReduction
        metrics = HistoryMetrics(samples: loadResult.samples)
        sessions = HistorySession.sessionize(loadResult.samples)
        networkTable = MacHistoryNetworkTablePresentation(samples: loadResult.samples)
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
            samples: surface.samples
        ))
    }

    nonisolated static func isActionEnabled(
        isLoading: Bool,
        surface: MacHistorySurfacePresentation?
    ) -> Bool {
        !isLoading && !(surface?.samples.isEmpty ?? true)
    }
}

actor MacHistorySurfaceLoader {
    private let loader = PingScopeIOSHistoryLoader()

    func load(
        store: any PingHistoryStore,
        hostID: UUID,
        range: HistoryRange,
        now: Date = Date()
    ) async -> MacHistorySurfacePresentation? {
        guard let result = await loader.load(store: store, hostID: hostID, range: range, now: now) else {
            return nil
        }
        return MacHistorySurfacePresentation(loadResult: result)
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
        guard let store = historySurfaceStore, let hostID = historySurfaceHost?.id else {
            historySurfacePresentation = nil
            isLoadingHistorySurface = false
            return
        }
        let range = historySurfaceRange
        isLoadingHistorySurface = true
        historySurfaceTask = Task { [weak self, historySurfaceLoader] in
            let loaded = await historySurfaceLoader.load(
                store: store,
                hostID: hostID,
                range: range,
                now: Date()
            )
            guard let self, !Task.isCancelled,
                  historySurfaceHost?.id == hostID,
                  historySurfaceRange == range else { return }
            if let loaded {
                historySurfacePresentation = loaded
            }
            isLoadingHistorySurface = false
        }
    }
}
