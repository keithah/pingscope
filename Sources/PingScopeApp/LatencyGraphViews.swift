import PingScopeCore
import SwiftUI

struct RecentSamplesView: View {
    let samples: [PingResult]
    var range: TimeRange? = nil

    var body: some View {
        ZStack {
            Table(samples) {
                TableColumn("Time") { result in
                    Text(result.timestamp, style: .time)
                }
                TableColumn("Result") { result in
                    if let latency = result.latency {
                        Text("\(Int(latency.milliseconds.rounded()))ms")
                    } else {
                        Text(result.failureReason?.userMessage ?? "Failed")
                            .foregroundStyle(.red)
                    }
                }
                TableColumn("Status") { result in
                    Text(result.isSuccess ? "OK" : "Failed")
                }
            }

            if samples.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 140)
    }

    private var emptyMessage: String {
        if let range {
            return "No samples in the last \(range.rawValue)."
        }
        return "No samples yet."
    }
}

struct LatencyGraph: View {
    let graphData: LatencyGraphData
    var showsAxes = false
    var color: Color = .accentColor

    init(samples: [PingResult], showsAxes: Bool = false, color: Color = .accentColor) {
        self.init(graphData: LatencyGraphData(samples: samples), showsAxes: showsAxes, color: color)
    }

    init(graphData: LatencyGraphData, showsAxes: Bool = false, color: Color = .accentColor) {
        self.graphData = graphData
        self.showsAxes = showsAxes
        self.color = color
    }

    var body: some View {
        HStack(spacing: showsAxes ? 6 : 0) {
            if showsAxes {
                LatencyGraphAxisLabels(scale: graphData.scale, hasData: graphData.hasLatencyData)
            }

            ZStack {
                graphCanvas(graphData: graphData)

                // Only claim the range is empty when it truly is. A window full
                // of failures still has samples -- they render as red marks.
                if graphData.isEmpty {
                    Text("No samples in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if showsAxes {
                LatencyGraphRightTicks(scale: graphData.scale)
            }
        }
        .accessibilityLabel("Latency graph")
    }

    private func graphCanvas(graphData: LatencyGraphData) -> some View {
        Canvas { context, size in
                // Bail out only when there is nothing at all to plot. During a
                // total outage every sample is a failure: the line stroke is a
                // no-op but the per-point loop must still stamp the red marks.
                guard !graphData.isEmpty else {
                    let rect = CGRect(origin: .zero, size: size)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.secondary.opacity(0.25)))
                    return
                }

                if showsAxes {
                    LatencyGraphGrid.draw(in: size, context: context, scale: graphData.scale)
                }

                let plotTop: CGFloat = showsAxes ? 6 : 0
                let plotBottom: CGFloat = showsAxes ? 6 : 0
                let plotHeight = max(size.height - plotTop - plotBottom, 1)

                let renderPoints = graphData.renderPoints(pixelWidth: size.width)
                let lineSegments = graphData.smoothedPathSegments(
                    size: size,
                    plotTop: plotTop,
                    plotBottom: plotBottom
                )

                for segment in lineSegments where segment.points.count > 1 {
                    var fillPath = Path()
                    fillPath.addPath(Path(segment.path))
                    fillPath.addLine(to: CGPoint(x: segment.points.last!.x, y: plotTop + plotHeight))
                    fillPath.addLine(to: CGPoint(x: segment.points[0].x, y: plotTop + plotHeight))
                    fillPath.closeSubpath()
                    context.fill(fillPath, with: .linearGradient(
                        Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: plotTop),
                        endPoint: CGPoint(x: 0, y: plotTop + plotHeight)
                    ))
                }

                for pointValue in renderPoints {
                    let x = pointValue.xPosition(sampleCount: graphData.sampleCount, width: size.width)
                    guard pointValue.latencyMilliseconds != nil else {
                        let failureMark = Path { mark in
                            mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                            mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                        }
                        context.stroke(failureMark, with: .color(.red.opacity(0.72)), lineWidth: 1.5)
                        continue
                    }
                }
                for segment in lineSegments {
                    context.stroke(
                        Path(segment.path),
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                }

        }
    }

}

struct LatencySparkline: View {
    let graphData: LatencyGraphData
    var color: Color = .accentColor

    init(samples: [PingResult], color: Color = .accentColor) {
        self.init(graphData: LatencyGraphData(samples: samples), color: color)
    }

    init(graphData: LatencyGraphData, color: Color = .accentColor) {
        self.graphData = graphData
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            guard graphData.points.count > 1 else { return }
            let lineSegments = graphData.smoothedPathSegments(size: size)
            for segment in lineSegments {
                context.stroke(
                    Path(segment.path),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

struct MultiHostLatencyGraph: View {
    let series: [HostLatencyGraphSeries]
    let graphData: MultiHostLatencyGraphData
    var showsAxes = false
    var showsLegend = true

    init(series: [HostLatencyGraphSeries], showsAxes: Bool = false, showsLegend: Bool = true) {
        self.init(
            series: series,
            graphData: MultiHostLatencyGraphData(series: series),
            showsAxes: showsAxes,
            showsLegend: showsLegend
        )
    }

    init(
        series: [HostLatencyGraphSeries],
        graphData: MultiHostLatencyGraphData,
        showsAxes: Bool = false,
        showsLegend: Bool = true
    ) {
        self.series = series
        self.graphData = graphData
        self.showsAxes = showsAxes
        self.showsLegend = showsLegend
    }

    var body: some View {
        HStack(spacing: showsAxes ? 6 : 0) {
            if showsAxes {
                LatencyGraphAxisLabels(scale: graphData.scale, hasData: graphData.hasLatencyData)
            }

            ZStack(alignment: .bottomLeading) {
                graphCanvas(graphData: graphData)

                if graphData.isEmpty {
                    Text("No samples in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showsLegend {
                    legend
                        .padding(8)
                }
            }

            if showsAxes {
                LatencyGraphRightTicks(scale: graphData.scale)
            }
        }
        .accessibilityLabel("All hosts latency graph")
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(graphData.visibleLegendSeries) { hostSeries in
                HStack(spacing: 4) {
                    Circle()
                        .fill(hostSeries.color)
                        .frame(width: 6, height: 6)
                    Text(hostSeries.host.displayName)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: hostSeries.isPrimary ? .semibold : .regular))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func graphCanvas(graphData: MultiHostLatencyGraphData) -> some View {
        Canvas { context, size in
                guard !graphData.isEmpty else {
                    let rect = CGRect(origin: .zero, size: size)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.secondary.opacity(0.25)))
                    return
                }

                if showsAxes {
                    LatencyGraphGrid.draw(in: size, context: context, scale: graphData.scale)
                }

                for hostSeries in graphData.drawableSeries {
                    draw(hostSeries, in: size, context: context, scale: graphData.scale)
                }
        }
    }

    private func draw(_ hostSeries: DrawableHostLatencyGraphSeries, in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let plotTop: CGFloat = showsAxes ? 6 : 0
        let plotBottom: CGFloat = showsAxes ? 6 : 0
        let plotHeight = max(size.height - plotTop - plotBottom, 1)

        let renderPoints = hostSeries.renderPoints(pixelWidth: size.width)
        for pointValue in renderPoints {
            let x = pointValue.xPosition(sampleCount: hostSeries.sampleCount, width: size.width)
            guard pointValue.latencyMilliseconds != nil else {
                if hostSeries.source.isPrimary {
                    let failureMark = Path { mark in
                        mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                        mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                    }
                    context.stroke(failureMark, with: .color(.red.opacity(0.55)), lineWidth: 1.2)
                }
                continue
            }
        }

        let lineSegments = hostSeries.smoothedPathSegments(
            size: size,
            scale: scale,
            plotTop: plotTop,
            plotBottom: plotBottom
        )
        for segment in lineSegments {
            context.stroke(
                Path(segment.path),
                with: .color(hostSeries.source.color.opacity(hostSeries.source.isPrimary ? 1 : 0.72)),
                lineWidth: hostSeries.source.isPrimary ? 2.2 : 1.5
            )
        }
    }

}

private struct LatencyGraphAxisLabels: View {
    let scale: LatencyGraphScale
    let hasData: Bool

    var body: some View {
        VStack(alignment: .trailing) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Text(hasData ? scale.label(for: value) : (value == 0 ? "0ms" : "--"))
                    .frame(height: 12, alignment: .center)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 34)
    }
}

private struct LatencyGraphRightTicks: View {
    let scale: LatencyGraphScale

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 6, height: 1)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 6)
        .padding(.vertical, 6)
    }
}

private enum LatencyGraphGrid {
    static func draw(in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let plotTop: CGFloat = 6
        let plotHeight = max(size.height - 12, 1)
        for tick in scale.tickMilliseconds {
            let normalized = min(max(tick / scale.axisMaximumMilliseconds, 0), 1)
            let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.secondary.opacity(tick == 0 ? 0.24 : 0.14)), lineWidth: 1)
        }
    }
}
