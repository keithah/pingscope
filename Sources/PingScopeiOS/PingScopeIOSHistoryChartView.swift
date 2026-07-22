import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

enum PingScopeIOSAveragePathBuilder {
    struct Segment<Line> {
        let line: Line?
        let first: CGPoint
        let last: CGPoint
    }

    static func build<Line>(
        segments: [[CGPoint]],
        makeLine: ([CGPoint]) -> Line
    ) -> [Segment<Line>] {
        segments.compactMap { points in
            guard let first = points.first, let last = points.last else { return nil }
            return Segment(
                line: points.count > 1 ? makeLine(points) : nil,
                first: first,
                last: last
            )
        }
    }
}

struct PingScopeIOSHistoryContentMemo<Key: Hashable, Value> {
    private var cache = BoundedMemo<Key, Value>(capacity: 4)

    mutating func resolve(_ key: Key, build: () -> Value) -> Value {
        cache.resolve(key, build: build)
    }
}

#if os(iOS)
public struct PingScopeIOSHistoryChartView: View {
    private struct ContentCacheKey: Hashable {
        let range: HistoryRange
        let samples: AppendOnlySequenceFingerprint<UUID>
        let startDate: Date
        let endDate: Date
        let selection: HistoryNetworkSelection
    }

    private struct ContentCache {
        let key: ContentCacheKey
        let networkPresentation: HistoryNetworkPresentation
        let visiblePresentation: PingScopeIOSHistoryPresentation
    }

    @MainActor
    private final class ContentMemo: ObservableObject {
        private var cache = PingScopeIOSHistoryContentMemo<ContentCacheKey, ContentCache>()

        init(presentation: PingScopeIOSHistoryPresentation?) {
            if let presentation {
                let initial = PingScopeIOSHistoryChartView.makeContentCache(presentation, selection: .all)
                _ = cache.resolve(initial.key) { initial }
            }
        }

        func resolve(
            _ presentation: PingScopeIOSHistoryPresentation,
            selection: HistoryNetworkSelection
        ) -> ContentCache {
            let key = PingScopeIOSHistoryChartView.contentCacheKey(for: presentation, selection: selection)
            return cache.resolve(key) {
                PingScopeIOSHistoryChartView.makeContentCache(presentation, selection: selection)
            }
        }
    }

    public let selectedRange: HistoryRange
    public let resolvedPresentation: PingScopeIOSResolvedHistoryPresentation
    @State private var networkSelection: HistoryNetworkSelection = .all
    @StateObject private var contentMemo: ContentMemo

    public init(
        selectedRange: HistoryRange,
        resolvedPresentation: PingScopeIOSResolvedHistoryPresentation
    ) {
        self.selectedRange = selectedRange
        self.resolvedPresentation = resolvedPresentation
        let presentation: PingScopeIOSHistoryPresentation? = if case let .content(content) = resolvedPresentation {
            content
        } else {
            nil
        }
        _contentMemo = StateObject(wrappedValue: ContentMemo(presentation: presentation))
    }

    public var body: some View {
        ScrollView {
            Group {
                switch resolvedPresentation {
                case .loading:
                    loadingCard
                case let .content(presentation):
                    historyContent(
                        presentation,
                        cache: contentMemo.resolve(presentation, selection: networkSelection)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func historyContent(_ presentation: PingScopeIOSHistoryPresentation, cache: ContentCache) -> some View {
        let networkPresentation = cache.networkPresentation
        let visiblePresentation = cache.visiblePresentation
        VStack(alignment: .leading, spacing: 16) {
            if let collectingText = presentation.collectingText {
                Label(collectingText, systemImage: "clock.badge.checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let emptyState = presentation.emptyState {
                emptyCard(emptyState)
            } else {
                HistoryLatencyGraphCard(
                    renderData: visiblePresentation.graphData,
                    graphPresentation: visiblePresentation.graphPresentation,
                    endpointLabelStyle: selectedRange.endpointLabelStyle,
                    status: overallStatus(visiblePresentation)
                )
                .frame(height: 218)

                statisticsStrip(visiblePresentation)
                if let digest = presentation.weeklyDigest {
                    weeklyDigestSection(digest)
                }
                if !presentation.incidentLog.incidents.isEmpty {
                    incidentsSection(presentation.incidentLog)
                }
                networksSection(networkPresentation)
                sessionsSection(visiblePresentation)
            }
        }
        .onChange(of: selectedRange) { _, _ in
            networkSelection = .all
        }
        .onChange(of: presentation.sourceSamples.first?.hostID) { _, _ in
            networkSelection = .all
        }
        .onChange(of: networkPresentation.cards.map(\.key)) { _, keys in
            if case let .network(key) = networkSelection, !keys.contains(key) {
                networkSelection = .all
            }
        }
    }

    private static func makeContentCache(
        _ presentation: PingScopeIOSHistoryPresentation,
        selection: HistoryNetworkSelection
    ) -> ContentCache {
        ContentCache(
            key: contentCacheKey(for: presentation, selection: selection),
            networkPresentation: HistoryNetworkPresentation(samples: presentation.sourceSamples, selection: selection),
            visiblePresentation: presentation.applyingNetworkSelection(selection)
        )
    }

    private static func contentCacheKey(
        for presentation: PingScopeIOSHistoryPresentation,
        selection: HistoryNetworkSelection
    ) -> ContentCacheKey {
        ContentCacheKey(
            range: presentation.range,
            samples: AppendOnlySequenceFingerprint(samples: presentation.sourceSamples),
            startDate: presentation.graphData.startDate,
            endDate: presentation.graphData.endDate,
            selection: selection
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(selectedRange.rawValue) history…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func statisticsStrip(_ presentation: PingScopeIOSHistoryPresentation) -> some View {
        HStack(spacing: 0) {
            ForEach(presentation.statistics, id: \.label) { statistic in
                VStack(spacing: 4) {
                    Text(statistic.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(statistic.value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sessionsSection(_ presentation: PingScopeIOSHistoryPresentation) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .font(.headline)

            ForEach(presentation.sessions) { session in
                HistorySessionCard(presentation: session)
            }
        }
    }

    private func weeklyDigestSection(_ digest: HistoryWeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly digest").font(.headline)
            HStack(spacing: 0) {
                digestMetric("Uptime", percentage(digest.uptimePercent))
                digestMetric("Incidents", "\(digest.incidentCount)")
                digestMetric("Downtime", duration(digest.totalDowntime))
                digestMetric("Network", digest.busiestInterfaceLabel ?? "--")
            }
            .padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func incidentsSection(_ log: HistoryIncidentLog) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("Incidents").font(.headline)
            ForEach(log.incidents) { incident in
                HStack(spacing: 10) {
                    Image(systemName: incident.isOngoing ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(incident.isOngoing ? .red : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(incident.isOngoing ? "Ongoing outage" : "Recovered outage")
                            .font(.subheadline.weight(.semibold))
                        Text(incident.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(incident.sampleCount) · \(duration(incident.duration))")
                        .font(.caption.monospacedDigit())
                }
                .padding(13)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func digestMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func percentage(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds >= 3_600 { return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private func networksSection(_ presentation: HistoryNetworkPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("By network")
                    .font(.headline)
                Spacer()
                Button {
                    networkSelection = .all
                } label: {
                    Label("All networks", systemImage: networkSelection == .all ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(networkSelection == .all ? .blue : .secondary)
                .accessibilityHint("Show all network samples in the graph and statistics")
            }

            ForEach(presentation.cards) { card in
                Button {
                    networkSelection = .network(card.key)
                } label: {
                    HistoryNetworkCard(
                        presentation: card,
                        isSelected: networkSelection == .network(card.key)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Filter the graph and statistics to this network")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("By network")
    }

    private func emptyCard(_ state: PingScopeIOSHistoryEmptyState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.blue)
            Text(state.title)
                .font(.headline)
            Text(state.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 34)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func overallStatus(_ presentation: PingScopeIOSHistoryPresentation) -> HealthStatus {
        presentation.sessions.map(\.status).max { statusRank($0) < statusRank($1) } ?? .noData
    }

    private func statusRank(_ status: HealthStatus) -> Int {
        switch status {
        case .noData: 0
        case .healthy: 1
        case .degraded: 2
        case .down: 3
        }
    }
}

private struct HistoryNetworkCard: View {
    let presentation: HistoryNetworkCardPresentation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Image(systemName: presentation.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(presentation.interfaceLabel) · \(presentation.sampleCountText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if presentation.hasVPN {
                    Text("VPN")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.14), in: Capsule())
                        .foregroundStyle(.purple)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.55))
            }

            HistoryNetworkSparkline(
                samples: presentation.sparklineSamples,
                color: statusColor
            )
            .frame(height: 28)

            HStack(spacing: 0) {
                metric("AVG", presentation.averageText)
                metric("P95", presentation.p95Text)
                metric("LOSS", presentation.lossText)
                metric("UPTIME", presentation.uptimeText)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.primary.opacity(0.05), lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.label), \(presentation.interfaceLabel), \(presentation.sampleCountText)")
        .accessibilityValue("Average \(presentation.averageText), p95 \(presentation.p95Text), loss \(presentation.lossText), uptime \(presentation.uptimeText)\(presentation.hasVPN ? ", VPN" : "")")
    }

    private var statusColor: Color {
        Color(iosStatusColor: presentation.status.iosStatusColor)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryNetworkSparkline: View {
    let samples: [PingResult]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let successes = samples.compactMap { sample -> (Date, Double)? in
                guard sample.isSuccess,
                      let latency = sample.latency?.milliseconds,
                      latency.isFinite else { return nil }
                return (sample.timestamp, latency)
            }
            guard let start = samples.map(\.timestamp).min(),
                  let end = samples.map(\.timestamp).max(),
                  !successes.isEmpty else { return }
            let duration = max(end.timeIntervalSince(start), 1)
            let maximum = max(successes.map(\.1).max() ?? 1, 1)
            let points = successes.map { timestamp, latency in
                CGPoint(
                    x: size.width * CGFloat(timestamp.timeIntervalSince(start) / duration),
                    y: size.height - size.height * CGFloat(latency / maximum)
                )
            }
            if points.count > 1 {
                context.stroke(
                    Path(LatencyCurve.smoothedPath(points: points, closed: false)),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            } else if let point = points.first {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .color(color)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HistoryLatencyGraphCard: View {
    let renderData: PingScopeIOSLatencyGraphData
    let graphPresentation: PingScopeIOSHistoryGraphPresentation
    let endpointLabelStyle: PingScopeIOSHistoryEndpointLabelStyle
    let status: HealthStatus

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Latency")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(graphPresentation.scale.label(for: graphPresentation.scale.axisMaximumMilliseconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawExtremaBand(context: &context, size: size)
                    let averagePaths = averageSegmentPaths(size: size)
                    drawAverageFill(context: &context, size: size, paths: averagePaths)
                    drawAverageLine(context: &context, paths: averagePaths)
                    drawFailureMarkers(context: &context, size: size)
                }
                .accessibilityLabel("Latency history graph")
            }

            HStack {
                endpointLabel(renderData.startDate)
                Spacer()
                endpointLabel(renderData.endDate)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private var graphColor: Color {
        status == .healthy ? .blue : Color(iosStatusColor: status.iosStatusColor)
    }

    @ViewBuilder
    private func endpointLabel(_ date: Date) -> some View {
        switch endpointLabelStyle {
        case .time:
            Text(date, format: .dateTime.hour().minute())
        case .compactDateTime:
            Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
        case .compactDate:
            Text(date, format: .dateTime.month(.abbreviated).day())
        }
    }

    private func averagePoints(_ values: [HistoryChartPoint], size: CGSize) -> [CGPoint] {
        values.map { point in
            CGPoint(x: xPosition(point.timestamp, size: size), y: yPosition(point.latencyMilliseconds, size: size))
        }
    }

    private func averageSegmentPaths(size: CGSize) -> [PingScopeIOSAveragePathBuilder.Segment<Path>] {
        PingScopeIOSAveragePathBuilder.build(
            segments: graphPresentation.averageLineSegments.map { averagePoints($0, size: size) }
        ) { points in
            Path(LatencyCurve.smoothedPath(points: points, closed: false))
        }
    }

    private func xPosition(_ date: Date, size: CGSize) -> CGFloat {
        let duration = max(renderData.endDate.timeIntervalSince(renderData.startDate), 1)
        let elapsed = date.timeIntervalSince(renderData.startDate)
        return size.width * CGFloat(min(max(elapsed / duration, 0), 1))
    }

    private func yPosition(_ milliseconds: Double, size: CGSize) -> CGFloat {
        let maximum = max(graphPresentation.scale.axisMaximumMilliseconds, 1)
        return size.height - size.height * CGFloat(min(max(milliseconds / maximum, 0), 1))
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.0, 0.5, 1.0] {
            path.move(to: CGPoint(x: 0, y: size.height * ratio))
            path.addLine(to: CGPoint(x: size.width, y: size.height * ratio))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.14)), lineWidth: 1)
    }

    private func drawExtremaBand(context: inout GraphicsContext, size: CGSize) {
        for segment in graphPresentation.extremaBandSegments {
            let upper = segment.map {
                CGPoint(x: xPosition($0.timestamp, size: size), y: yPosition($0.maximumMilliseconds, size: size))
            }
            let lower = segment.reversed().map {
                CGPoint(x: xPosition($0.timestamp, size: size), y: yPosition($0.minimumMilliseconds, size: size))
            }
            guard let first = upper.first else { continue }
            var path = Path()
            path.move(to: first)
            for point in upper.dropFirst() { path.addLine(to: point) }
            for point in lower { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(graphColor.opacity(0.10)))
        }
    }

    private func drawAverageFill(
        context: inout GraphicsContext,
        size: CGSize,
        paths: [PingScopeIOSAveragePathBuilder.Segment<Path>]
    ) {
        for averagePath in paths {
            guard var path = averagePath.line else { continue }
            path.addLine(to: CGPoint(x: averagePath.last.x, y: size.height))
            path.addLine(to: CGPoint(x: averagePath.first.x, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(
                Gradient(colors: [graphColor.opacity(0.24), graphColor.opacity(0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
    }

    private func drawAverageLine(
        context: inout GraphicsContext,
        paths: [PingScopeIOSAveragePathBuilder.Segment<Path>]
    ) {
        for averagePath in paths {
            if let path = averagePath.line {
                context.stroke(
                    path,
                    with: .color(graphColor),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
            } else {
                let point = averagePath.first
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(graphColor))
            }
        }
    }

    private func drawFailureMarkers(context: inout GraphicsContext, size: CGSize) {
        for marker in graphPresentation.failureMarkers {
            let x = xPosition(marker.timestamp, size: size)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                line,
                with: .color(Color.red.opacity(0.34)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.fill(
                Path(ellipseIn: CGRect(x: x - 3, y: size.height - 9, width: 6, height: 6)),
                with: .color(.red)
            )
        }
    }
}

private struct HistorySessionCard: View {
    let presentation: PingScopeIOSHistorySessionPresentation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(iosStatusColor: presentation.status.iosStatusColor))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(presentation.session.startDate, style: .time)
                    Text("–")
                    Text(presentation.session.endDate, style: .time)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)

                HistorySessionSparkline(
                    renderData: presentation.graphData,
                    color: Color(iosStatusColor: presentation.status.iosStatusColor)
                )
                .frame(height: 24)
            }

            Spacer(minLength: 4)

            Text(presentation.averageText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }
}

private struct HistorySessionSparkline: View {
    let renderData: PingScopeIOSLatencyGraphData
    let color: Color

    var body: some View {
        Canvas { context, size in
            let duration = max(renderData.endDate.timeIntervalSince(renderData.startDate), 1)
            let maximum = max(renderData.scale.axisMaximumMilliseconds, 1)
            let points = renderData.points.map { point in
                CGPoint(
                    x: size.width * CGFloat(min(max(point.timestamp.timeIntervalSince(renderData.startDate) / duration, 0), 1)),
                    y: size.height - size.height * CGFloat(min(max(point.latencyMilliseconds / maximum, 0), 1))
                )
            }
            guard points.count > 1 else { return }
            context.stroke(
                Path(LatencyCurve.smoothedPath(points: points, closed: false)),
                with: .color(color),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}
#endif
