import Foundation
import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

@MainActor
final class PingScopeIOSPathProjectionMemo<Key: Hashable, Value> {
    private var values = BoundedMemo<Key, Value>(capacity: 8)

    var count: Int { values.count }

    func prepare(forSeriesCount seriesCount: Int) {
        values.setCapacity(max(8, seriesCount))
    }

    func resolve(_ key: Key, build: () -> Value) -> Value {
        values.resolve(key, build: build)
    }
}

#if os(iOS)
struct SignalHeroGraphCard: View {
    let renderData: PingScopeIOSLatencyGraphData
    let range: TimeRange
    let color: Color
    @Binding var scrubbedLatencyMilliseconds: Double?
    let onStepRange: (Int) -> Void
    let onSwipeHost: (Int) -> Void
    @StateObject private var pathMemo = PingScopeIOSSmoothedPathMemo()

    private let yAxisWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                yAxisLabels
                    .frame(width: yAxisWidth)
                GeometryReader { proxy in
                    Canvas { context, size in
                        drawGrid(context: &context, size: size)
                        let linePath = drawLinePath(size: size)
                        drawFill(linePath: linePath, context: &context, size: size)
                        drawLine(linePath: linePath, context: &context)
                    }
                    .gesture(graphDrag(size: proxy.size))
                    .simultaneousGesture(magnifyGesture)
                }
            }
            HStack {
                Color.clear.frame(width: yAxisWidth + 8)
                Text(renderData.startDate, style: .time)
                Spacer()
                Text("now")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 18)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing) {
            ForEach(Array(renderData.scale.tickMilliseconds.enumerated()), id: \.offset) { _, tick in
                Text(renderData.scale.label(for: tick))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                if tick != renderData.scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var graphColor: Color {
        color
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value > 1.08 {
                    onStepRange(1)
                } else if value < 0.92 {
                    onStepRange(-1)
                }
            }
    }

    private func graphDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(max(value.location.x, 0), max(size.width, 1))
                scrubbedLatencyMilliseconds = latency(atX: x, width: size.width)
            }
            .onEnded { value in
                if abs(value.translation.width) > 72, abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    onSwipeHost(value.translation.width < 0 ? 1 : -1)
                }
                scrubbedLatencyMilliseconds = nil
            }
    }

    private func latency(atX x: CGFloat, width: CGFloat) -> Double? {
        let ratio = min(max(Double(x / max(width, 1)), 0), 1)
        let targetDate = renderData.startDate.addingTimeInterval(range.duration * ratio)
        return PingScopeIOSLatencyGraphPoint.nearest(
            to: targetDate,
            in: renderData.points
        )?.latencyMilliseconds
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.0, 0.5, 1.0] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.14)), lineWidth: 1)
    }

    private func drawLinePath(size: CGSize) -> Path? {
        guard renderData.points.count > 1 else { return nil }
        return pathMemo.path(
            key: .init(renderData: renderData, size: size)
        ) {
            Path(LatencyCurve.smoothedPath(points: graphPoints(size: size), closed: false))
        }
    }

    private func graphPoints(size: CGSize) -> [CGPoint] {
        let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
        return renderData.points.map { pointValue in
            let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
            let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
            let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
            return CGPoint(x: x, y: y)
        }
    }

    private func drawFill(linePath: Path?, context: inout GraphicsContext, size: CGSize) {
        guard renderData.points.count > 1, var fillPath = linePath else { return }
        let last = renderData.points.last!
        let first = renderData.points.first!
        let lastX = size.width * CGFloat(min(max(last.timestamp.timeIntervalSince(renderData.startDate) / range.duration, 0), 1))
        let firstX = size.width * CGFloat(min(max(first.timestamp.timeIntervalSince(renderData.startDate) / range.duration, 0), 1))
        fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
        fillPath.addLine(to: CGPoint(x: firstX, y: size.height))
        fillPath.closeSubpath()
        context.fill(fillPath, with: .linearGradient(
            Gradient(colors: [graphColor.opacity(0.28), graphColor.opacity(0.0)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
    }

    private func drawLine(linePath: Path?, context: inout GraphicsContext) {
        guard let path = linePath else { return }
        context.stroke(path, with: .color(graphColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

struct PingScopeIOSAllHostsSignalHeroGraphCard: View {
    private struct RenderSeries {
        let hostID: UUID
        let renderData: PingScopeIOSLatencyGraphData
        let color: Color
    }

    let presentation: PingScopeIOSAllHostsGraphPresentation
    let range: TimeRange
    @Binding var scrubbedLatencyMilliseconds: Double?
    let onStepRange: (Int) -> Void
    @StateObject private var pathMemo = PingScopeIOSSmoothedPathMemo()

    private let yAxisWidth: CGFloat = 44

    var body: some View {
        let renderSeries = Self.makeRenderSeries(from: presentation.series)
        let scale = presentation.scale
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                yAxisLabels(scale: scale)
                    .frame(width: yAxisWidth)
                GeometryReader { proxy in
                    ZStack {
                        Canvas { context, size in
                            drawGrid(context: &context, size: size)
                            for series in renderSeries {
                                drawLine(series, scale: scale, context: &context, size: size)
                            }
                        }
                        if !Self.hasLatencyData(in: renderSeries) {
                            Text("No samples in range")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .gesture(graphDrag(size: proxy.size))
                    .simultaneousGesture(magnifyGesture)
                }
            }
            HStack {
                Color.clear.frame(width: yAxisWidth + 8)
                Text(presentation.startDate, style: .time)
                Spacer()
                Text("now")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 18)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .accessibilityLabel("All hosts latency graph")
    }

    private static func makeRenderSeries(
        from series: [PingScopeIOSAllHostsPreparedGraphSeries]
    ) -> [RenderSeries] {
        series.map { source in
            return RenderSeries(
                hostID: source.hostID,
                renderData: source.renderData,
                color: source.identityColor.swiftUIColor
            )
        }
    }

    private static func hasLatencyData(in renderSeries: [RenderSeries]) -> Bool {
        renderSeries.contains { !$0.renderData.points.isEmpty }
    }

    private func yAxisLabels(scale: LatencyGraphScale) -> some View {
        VStack(alignment: .trailing) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, tick in
                Text(scale.label(for: tick))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                if tick != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value > 1.08 {
                    onStepRange(1)
                } else if value < 0.92 {
                    onStepRange(-1)
                }
            }
    }

    private func graphDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(max(value.location.x, 0), max(size.width, 1))
                scrubbedLatencyMilliseconds = latency(atX: x, width: size.width)
            }
            .onEnded { _ in
                scrubbedLatencyMilliseconds = nil
            }
    }

    private func latency(atX x: CGFloat, width: CGFloat) -> Double? {
        let ratio = min(max(Double(x / max(width, 1)), 0), 1)
        let targetDate = presentation.startDate.addingTimeInterval(range.duration * ratio)
        return PingScopeIOSLatencyGraphPoint.nearest(
            to: targetDate,
            in: presentation.chronologicalPoints
        )?.latencyMilliseconds
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.0, 0.5, 1.0] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.14)), lineWidth: 1)
    }

    private func drawLine(
        _ series: RenderSeries,
        scale: LatencyGraphScale,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard series.renderData.points.count > 1 else { return }
        pathMemo.prepare(forSeriesCount: presentation.series.count)
        context.stroke(
            pathMemo.path(
                key: .init(renderData: series.renderData, size: size, hostID: series.hostID)
            ) {
                let axisMaximum = max(scale.axisMaximumMilliseconds, 1)
                let points = series.renderData.points.map { pointValue in
                    let elapsed = pointValue.timestamp.timeIntervalSince(presentation.startDate)
                    let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
                    let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMaximum, 1)))
                    return CGPoint(x: x, y: y)
                }
                return Path(LatencyCurve.smoothedPath(points: points, closed: false))
            },
            with: .color(series.color),
            style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round)
        )
    }
}

struct PingScopeIOSSparkline: View {
    let renderData: PingScopeIOSLatencyGraphData
    let color: Color
    @StateObject private var pathMemo = PingScopeIOSSmoothedPathMemo()

    var body: some View {
        Canvas { context, size in
            guard renderData.points.count > 1 else { return }
            let path = pathMemo.path(key: .init(renderData: renderData, size: size)) {
                let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
                let points = renderData.points.map { pointValue in
                    let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
                    let x = size.width * CGFloat(min(max(elapsed / max(renderData.endDate.timeIntervalSince(renderData.startDate), 1), 0), 1))
                    let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
                    return CGPoint(x: x, y: y)
                }
                return Path(LatencyCurve.smoothedPath(points: points, closed: false))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

@MainActor
private final class PingScopeIOSSmoothedPathMemo: ObservableObject {
    struct Key: Hashable {
        let hostID: UUID?
        let pointCount: Int
        let firstTimestamp: Date?
        let lastTimestamp: Date?
        let firstLatency: Double?
        let lastLatency: Double?
        let startDate: Date
        let endDate: Date
        let axisMaximum: Double
        let width: CGFloat
        let height: CGFloat

        init(renderData: PingScopeIOSLatencyGraphData, size: CGSize, hostID: UUID? = nil) {
            self.hostID = hostID
            pointCount = renderData.points.count
            firstTimestamp = renderData.points.first?.timestamp
            lastTimestamp = renderData.points.last?.timestamp
            firstLatency = renderData.points.first?.latencyMilliseconds
            lastLatency = renderData.points.last?.latencyMilliseconds
            startDate = renderData.startDate
            endDate = renderData.endDate
            axisMaximum = renderData.scale.axisMaximumMilliseconds
            width = size.width
            height = size.height
        }
    }

    private let paths = PingScopeIOSPathProjectionMemo<Key, Path>()

    func prepare(forSeriesCount seriesCount: Int) {
        paths.prepare(forSeriesCount: seriesCount)
    }

    func path(key: Key, build: () -> Path) -> Path {
        paths.resolve(key, build: build)
    }
}

#endif
