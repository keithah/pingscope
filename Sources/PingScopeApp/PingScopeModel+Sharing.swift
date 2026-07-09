import AppKit
import PingScopeCore

extension PingScopeModel {
    func shareGraph(options: PingScopeShareGraphOptions) {
        Task { [weak self] in
            guard let self else { return }
            let presentation = await self.shareGraphPresentation(options: options)
            self.presentShareGraph(presentation)
        }
    }

    func shareGraphPresentation(options: PingScopeShareGraphOptions) async -> PingScopeShareGraphPresentation {
        let now = Date()
        let snapshot = snapshot
        let showsAllHosts = shareGraphShowsAllHosts(scope: options.scope)
        let primaryHost = snapshot.primaryHost
        let range = options.range
        let visibleHistorySamples: [PingResult]
        if showsAllHosts {
            visibleHistorySamples = []
        } else if let hostID = primaryHost?.id {
            visibleHistorySamples = await runtime.historySamples(
                hostID: hostID,
                since: now.addingTimeInterval(-range.duration),
                limit: Self.visibleHistorySampleLimit(for: range)
            )
        } else {
            visibleHistorySamples = []
        }
        let displayPresentation = PingScopeDisplayPresentation(
            snapshot: snapshot,
            selectedRange: range,
            visibleHistorySamples: visibleHistorySamples,
            includesAllHosts: showsAllHosts,
            presenter: presenter,
            now: now
        )
        let state = presenter.rangeStatusState(for: primaryHost, health: snapshot.primaryHealth, range: range)
        let shareStatus: (text: String, color: StatusColor)
        if showsAllHosts {
            shareStatus = allHostShareStatus(snapshot: snapshot)
        } else {
            shareStatus = (presenter.rangeStatusLabel(for: snapshot.primaryHealth, range: range), state.color)
        }
        return PingScopeShareGraphPresentation(
            range: range,
            title: showsAllHosts ? "All Hosts" : (primaryHost?.displayName ?? "No Host"),
            subtitle: shareGraphSubtitle(primaryHost: primaryHost, showsAllHosts: showsAllHosts, snapshot: snapshot),
            statusText: shareStatus.text,
            statusColor: shareStatus.color,
            generatedAt: now,
            showsAllHosts: showsAllHosts,
            colorScheme: options.appearance.resolvedColorScheme,
            includesTable: options.includesTable,
            sampleRows: options.includesTable
                ? shareGraphSampleRows(
                    snapshot: snapshot,
                    displayPresentation: displayPresentation,
                    range: range,
                    showsAllHosts: showsAllHosts,
                    now: now
                )
                : [],
            displayPresentation: displayPresentation
        )
    }

    private func shareGraphShowsAllHosts(scope: PingScopeShareGraphScope) -> Bool {
        switch scope {
        case .currentView: popoverShowsAllHosts
        case .singleHost: false
        case .allHosts: true
        }
    }

    private func shareGraphSampleRows(
        snapshot: RuntimeSnapshot,
        displayPresentation: PingScopeDisplayPresentation,
        range: TimeRange,
        showsAllHosts: Bool,
        now: Date
    ) -> [PingScopeShareSampleRow] {
        if showsAllHosts {
            var newestRows: [PingScopeShareSampleRow] = []
            newestRows.reserveCapacity(6)
            for series in displayPresentation.allHostGraphSeries {
                for sample in series.samples {
                    insertNewestShareRow(
                        shareGraphSampleRow(sample, hostName: series.host.displayName),
                        into: &newestRows,
                        limit: 6
                    )
                }
            }
            return newestRows
        }
        return displayPresentation.recentVisibleSamples.prefix(6).map { result in
            shareGraphSampleRow(result, hostName: nil)
        }
    }

    private func insertNewestShareRow(
        _ row: PingScopeShareSampleRow,
        into rows: inout [PingScopeShareSampleRow],
        limit: Int
    ) {
        let insertionIndex = rows.firstIndex { $0.timestamp < row.timestamp } ?? rows.endIndex
        rows.insert(row, at: insertionIndex)
        if rows.count > limit {
            rows.removeLast()
        }
    }

    private func shareGraphSampleRow(_ result: PingResult, hostName: String?) -> PingScopeShareSampleRow {
        PingScopeShareSampleRow(
            id: result.id,
            timestamp: result.timestamp,
            hostName: hostName,
            resultText: shareGraphResultText(result),
            statusText: result.isSuccess ? "OK" : "Failed",
            isSuccess: result.isSuccess
        )
    }

    private func shareGraphResultText(_ result: PingResult) -> String {
        if let latency = result.latency {
            return "\(Int(latency.milliseconds.rounded()))ms"
        }
        return result.failureReason?.userMessage ?? "Failed"
    }

    private func allHostShareStatus(snapshot: RuntimeSnapshot) -> (text: String, color: StatusColor) {
        let measuredStatuses = snapshot.hosts.compactMap { host -> HealthStatus? in
            guard host.isEnabled,
                  let health = snapshot.healthByHost[host.id],
                  health.latestResult != nil else {
                return nil
            }
            return health.status
        }
        guard !measuredStatuses.isEmpty else {
            return ("No Recent Data", .gray)
        }
        if measuredStatuses.contains(.down) {
            return ("Issues Detected", .red)
        }
        if measuredStatuses.contains(.degraded) {
            return ("Degraded", .yellow)
        }
        return ("Healthy", .green)
    }

    private func shareGraphSubtitle(primaryHost: HostConfig?, showsAllHosts: Bool, snapshot: RuntimeSnapshot) -> String {
        if showsAllHosts {
            let enabledCount = snapshot.hosts.reduce(0) { count, host in
                count + (host.isEnabled ? 1 : 0)
            }
            return "\(enabledCount) enabled hosts"
        }
        guard let primaryHost else { return "No monitored host" }
        if let port = primaryHost.port {
            return "\(primaryHost.method.displayName) \(primaryHost.address):\(port)"
        }
        return "\(primaryHost.method.displayName) \(primaryHost.address)"
    }

    private func presentShareGraph(_ presentation: PingScopeShareGraphPresentation) {
        guard let image = PingScopeShareGraphRenderer.image(for: presentation) else { return }
        if let sourceView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView {
            let picker = NSSharingServicePicker(items: [image])
            picker.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }
}
