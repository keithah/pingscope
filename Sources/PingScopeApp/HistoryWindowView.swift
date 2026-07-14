import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var model: PingScopeModel
    @State private var reportPresentation: MacHistoryReportPresentation?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                Group {
                    if model.isLoadingHistorySurface, model.historySurfacePresentation == nil {
                        ProgressView("Loading history…")
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else if let presentation = model.historySurfacePresentation,
                              !presentation.samples.isEmpty {
                        content(presentation)
                    } else {
                        ContentUnavailableView(
                            "No History Yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Ping samples for this host and range will appear here as they are collected.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.prepareHistorySurface() }
        .onChange(of: model.historySurfaceRefreshKey) { _, _ in model.refreshHistorySurface() }
        .sheet(item: $reportPresentation) { report in
            MacHistoryReportSheet(report: report.content)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Host", selection: $model.historySurfaceHostID) {
                ForEach(model.configuredHosts) { host in
                    Text(host.displayName).tag(host.id as UUID?)
                }
            }
            .frame(width: 210)
            .accessibilityIdentifier("history.hostPicker")

            Picker("Range", selection: $model.historySurfaceRange) {
                ForEach(HistoryRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("history.rangePicker")

            Spacer()
            if model.isLoadingHistorySurface {
                ProgressView().controlSize(.small)
            }
            Button {
                reportPresentation = MacHistoryReportPresentation.make(
                    host: model.historySurfaceHost,
                    surface: model.historySurfacePresentation
                )
            } label: {
                Label("Report", systemImage: "square.and.arrow.up")
            }
            .disabled(!MacHistoryReportPresentation.isActionEnabled(
                isLoading: model.isLoadingHistorySurface,
                surface: model.historySurfacePresentation
            ))
            .help("Preview and share a History report")
            .accessibilityIdentifier("history.reportButton")

            Button {
                model.refreshHistorySurface()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh history")
            .accessibilityLabel("Refresh history")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func content(_ presentation: MacHistorySurfacePresentation) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if presentation.isCollecting {
                Label("Collecting data for the full selected range", systemImage: "clock.badge")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HistoryLatencyChart(presentation: presentation)
                .frame(height: 245)
                .accessibilityIdentifier("history.latencyChart")

            metricStrip(presentation.metrics)

            historySection("Sessions") {
                VStack(spacing: 0) {
                    ForEach(Array(presentation.sessions.enumerated()), id: \.offset) { _, session in
                        HistorySessionRow(session: session)
                        if session != presentation.sessions.last { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            }

            historySection("By network") {
                HistoryNetworkTable(presentation: presentation.networkTable)
            }
        }
    }

    private func metricStrip(_ metrics: HistoryMetrics) -> some View {
        HStack(spacing: 0) {
            metric("Avg", latency(metrics.averageMilliseconds))
            metric("p95", latency(metrics.p95Milliseconds))
            metric("Loss", percent(metrics.lossPercent), tint: metrics.lossPercent > 0 ? .red : .primary)
            metric("Outages", "\(metrics.outageCount)", tint: metrics.outageCount > 0 ? .red : .primary)
            metric("Uptime", percent(metrics.uptimePercent))
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History metrics")
    }

    private func metric(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    private func historySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func latency(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) ms" } ?? "--"
    }

    private func percent(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
    }
}

private struct HistoryLatencyChart: View {
    let presentation: MacHistorySurfacePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latency").font(.headline)
                Spacer()
                Text("\(presentation.range.rawValue) · \(presentation.samples.count) samples")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let points = chartPoints(in: geometry.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.18))
                    if points.count > 1 {
                        let line = Path(LatencyCurve.smoothedPath(points: points, closed: false))
                        areaPath(points: points, height: geometry.size.height)
                            .fill(LinearGradient(colors: [.green.opacity(0.28), .yellow.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom))
                        line.stroke(
                            LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    ForEach(Array(presentation.chartReduction.buckets.enumerated()), id: \.offset) { index, bucket in
                        if bucket.failureCount > 0 {
                            Capsule()
                                .fill(.red)
                                .frame(width: 3, height: 14)
                                .position(x: xPosition(index: index, width: geometry.size.width), y: geometry.size.height - 10)
                        }
                    }
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let points = presentation.chartReduction.averageLinePoints
        guard !points.isEmpty else { return [] }
        let maximum = max(points.map(\.latencyMilliseconds).max() ?? 1, 1)
        let span = max(presentation.endingAt.timeIntervalSince(presentation.cutoff), 1)
        return points.map {
            CGPoint(
                x: size.width * $0.timestamp.timeIntervalSince(presentation.cutoff) / span,
                y: size.height - 18 - (size.height - 30) * $0.latencyMilliseconds / maximum
            )
        }
    }

    private func areaPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = Path(LatencyCurve.smoothedPath(points: points, closed: false))
        path.addLine(to: CGPoint(x: points.last!.x, y: height))
        path.addLine(to: CGPoint(x: points.first!.x, y: height))
        path.closeSubpath()
        return path
    }

    private func xPosition(index: Int, width: CGFloat) -> CGFloat {
        let count = max(presentation.chartReduction.buckets.count - 1, 1)
        return width * CGFloat(index) / CGFloat(count)
    }
}

private struct HistorySessionRow: View {
    let session: HistorySession

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(statusColor: session.status.statusColor)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.startDate.formatted(date: .abbreviated, time: .shortened)) – \(session.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.weight(.semibold))
                Text("\(session.samples.count) samples")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            HistoryMiniSparkline(samples: session.sparklineSamples, color: Color(statusColor: session.status.statusColor))
                .frame(width: 100, height: 28)
            Text("Avg \(session.metrics.averageMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "--")")
                .font(.caption.monospacedDigit())
            if session.hasOutage {
                Label("\(session.metrics.outageCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryMiniSparkline: View {
    let samples: [PingResult]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let values = samples.compactMap { $0.latency?.milliseconds }
            if values.count > 1 {
                let maximum = max(values.max() ?? 1, 1)
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: geometry.size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: geometry.size.height - geometry.size.height * value / maximum
                    )
                }
                Path(LatencyCurve.smoothedPath(points: points, closed: false))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }
}

private struct HistoryNetworkTable: View {
    let presentation: MacHistoryNetworkTablePresentation

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            GridRow {
                header("Network"); header("Interface"); header("Samples")
                header("Avg"); header("p95"); header("Loss"); header("Uptime")
            }
            Divider().gridCellColumns(7)
            ForEach(presentation.rows) { row in
                GridRow {
                    HStack(spacing: 6) {
                        Image(systemName: row.systemImage).foregroundStyle(.secondary).frame(width: 16)
                        Text(row.label).lineLimit(1)
                        if row.hasVPN {
                            Text("VPN").font(.system(size: 9, weight: .bold)).foregroundStyle(.purple)
                        }
                    }
                    Text(row.interfaceLabel); Text("\(row.sampleCount)")
                    Text(row.averageText); Text(row.p95Text); Text(row.lossText); Text(row.uptimeText)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History by network")
        .accessibilityIdentifier("history.networkTable")
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
