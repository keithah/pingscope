import PingScopeCore
import SwiftUI

struct RecentSamplesView<Samples: Sequence<PingResult>>: View {
    let samples: Samples
    var range: TimeRange? = nil

    var body: some View {
        let sampleArray = Array(samples)

        ZStack {
            Table(sampleArray) {
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

            if sampleArray.isEmpty {
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

    init(samples: [PingResult], showsAxes: Bool = false) {
        self.init(graphData: LatencyGraphData(samples: samples), showsAxes: showsAxes)
    }

    init(graphData: LatencyGraphData, showsAxes: Bool = false) {
        self.graphData = graphData
        self.showsAxes = showsAxes
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
        GeometryReader { proxy in
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

                let maxValue = graphData.scale.axisMaximumMilliseconds
                var path = Path()
                var isDrawingSegment = false
                let plotTop: CGFloat = showsAxes ? 6 : 0
                let plotBottom: CGFloat = showsAxes ? 6 : 0
                let plotHeight = max(size.height - plotTop - plotBottom, 1)

                for pointValue in graphData.points {
                    let x = size.width * CGFloat(pointValue.index) / CGFloat(max(graphData.points.count - 1, 1))
                    guard let value = pointValue.latencyMilliseconds else {
                        let failureMark = Path { mark in
                            mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                            mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                        }
                        context.stroke(failureMark, with: .color(.red.opacity(0.72)), lineWidth: 1.5)
                        isDrawingSegment = false
                        continue
                    }

                    let normalized = min(value / maxValue, 1)
                    let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
                    let point = CGPoint(x: x, y: y)
                    if !isDrawingSegment {
                        path.move(to: point)
                        isDrawingSegment = true
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 2)

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        let visibleSeries = series.filter { !$0.samples.isEmpty }.prefix(4)

        return HStack(spacing: 8) {
            ForEach(Array(visibleSeries)) { hostSeries in
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
        GeometryReader { proxy in
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func draw(_ hostSeries: DrawableHostLatencyGraphSeries, in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let maxValue = scale.axisMaximumMilliseconds
        let plotTop: CGFloat = showsAxes ? 6 : 0
        let plotBottom: CGFloat = showsAxes ? 6 : 0
        let plotHeight = max(size.height - plotTop - plotBottom, 1)
        var path = Path()
        var isDrawingSegment = false

        for pointValue in hostSeries.points {
            let x = size.width * CGFloat(pointValue.index) / CGFloat(max(hostSeries.points.count - 1, 1))
            guard let value = pointValue.latencyMilliseconds else {
                if hostSeries.source.isPrimary {
                    let failureMark = Path { mark in
                        mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                        mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                    }
                    context.stroke(failureMark, with: .color(.red.opacity(0.55)), lineWidth: 1.2)
                }
                isDrawingSegment = false
                continue
            }

            let normalized = min(value / maxValue, 1)
            let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
            let point = CGPoint(x: x, y: y)
            if !isDrawingSegment {
                path.move(to: point)
                isDrawingSegment = true
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(hostSeries.source.color.opacity(hostSeries.source.isPrimary ? 1 : 0.72)),
            lineWidth: hostSeries.source.isPrimary ? 2.2 : 1.5
        )
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
