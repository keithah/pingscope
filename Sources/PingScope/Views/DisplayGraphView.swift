import SwiftUI

struct DisplayGraphView: View {
    let points: [DisplayViewModel.GraphPoint]

    private let gridLineCount = 4
    private let yAxisWidth: CGFloat = 36
    private let plotPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            if points.isEmpty {
                emptyState
            } else {
                chartWithAxis(in: proxy.size)
            }
        }
        .frame(minHeight: 44)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
            .overlay {
                Text("No samples yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func chartWithAxis(in size: CGSize) -> some View {
        let yBounds = latencyBounds(points)
        let chartSize = CGSize(width: size.width - yAxisWidth, height: size.height)

        HStack(alignment: .top, spacing: 0) {
            yAxisLabels(bounds: yBounds, height: size.height)
                .frame(width: yAxisWidth)

            chartArea(in: chartSize, yBounds: yBounds)
        }
    }

    private func yAxisLabels(bounds: ClosedRange<Double>, height: CGFloat) -> some View {
        let labels = yAxisValues(for: bounds)

        return GeometryReader { _ in
            ZStack(alignment: .trailing) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, value in
                    let normalizedY = (value - bounds.lowerBound) / max(0.001, bounds.upperBound - bounds.lowerBound)
                    let yPosition = (1 - normalizedY) * height

                    Text("\(Int(value.rounded()))")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: yAxisWidth / 2 - 2, y: yPosition)
                }
            }
        }
    }

    private func yAxisValues(for bounds: ClosedRange<Double>) -> [Double] {
        let range = bounds.upperBound - bounds.lowerBound
        let step = range / Double(gridLineCount)

        return (0...gridLineCount).map { bounds.lowerBound + Double($0) * step }
    }

    @ViewBuilder
    private func chartArea(in size: CGSize, yBounds: ClosedRange<Double>) -> some View {
        let xBounds = dateBounds(points)

        ZStack {
            // Activity Monitor-like background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }

            // Grid lines
            gridLines(in: size, yBounds: yBounds)

            // Gradient fill under the line
            areaFill(in: size, xBounds: xBounds, yBounds: yBounds)

            // Line path
            linePath(in: size, xBounds: xBounds, yBounds: yBounds)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Data point dots
            dataPointDots(in: size, xBounds: xBounds, yBounds: yBounds)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func gridLines(in size: CGSize, yBounds: ClosedRange<Double>) -> some View {
        let yValues = yAxisValues(for: yBounds)

        return Canvas { context, canvasSize in
            let lineColor = Color(nsColor: .separatorColor).opacity(0.35)

            // Horizontal grid lines
            for value in yValues {
                let normalizedY = (value - yBounds.lowerBound) / max(0.001, yBounds.upperBound - yBounds.lowerBound)
                let y = (1 - normalizedY) * canvasSize.height

                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))

                context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
            }

            // Vertical grid lines (4 segments)
            let verticalCount = 4
            for i in 1..<verticalCount {
                let x = canvasSize.width * CGFloat(i) / CGFloat(verticalCount)

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))

                context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
            }
        }
    }

    private func linePath(in size: CGSize, xBounds: ClosedRange<TimeInterval>, yBounds: ClosedRange<Double>) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let position = positionForPoint(point, in: size, xBounds: xBounds, yBounds: yBounds)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
    }

    private func areaFill(in size: CGSize, xBounds: ClosedRange<TimeInterval>, yBounds: ClosedRange<Double>) -> some View {
        Canvas { context, canvasSize in
            guard points.count >= 2,
                  let firstPoint = points.first,
                  let lastPoint = points.last
            else {
                return
            }

            let first = positionForPoint(firstPoint, in: canvasSize, xBounds: xBounds, yBounds: yBounds)
            let last = positionForPoint(lastPoint, in: canvasSize, xBounds: xBounds, yBounds: yBounds)
            let baselineY = canvasSize.height - plotPadding

            var area = linePath(in: canvasSize, xBounds: xBounds, yBounds: yBounds)
            area.addLine(to: CGPoint(x: last.x, y: baselineY))
            area.addLine(to: CGPoint(x: first.x, y: baselineY))
            area.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: Color.accentColor.opacity(0.28), location: 0),
                .init(color: Color.accentColor.opacity(0.0), location: 1)
            ])

            context.fill(
                area,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: plotPadding),
                    endPoint: CGPoint(x: 0, y: baselineY)
                )
            )
        }
    }

    private func dataPointDots(in size: CGSize, xBounds: ClosedRange<TimeInterval>, yBounds: ClosedRange<Double>) -> some View {
        Canvas { context, _ in
            let count = points.count
            let (radius, opacity): (CGFloat, Double)

            switch count {
            case 0 ..< 80:
                radius = 2.0
                opacity = 0.9
            case 80 ..< 300:
                radius = 1.6
                opacity = 0.65
            case 300 ..< 1_000:
                radius = 1.2
                opacity = 0.45
            default:
                radius = 0.9
                opacity = 0.3
            }

            let dotColor = Color.accentColor.opacity(opacity)

            for point in points {
                let position = positionForPoint(point, in: size, xBounds: xBounds, yBounds: yBounds)

                // Simple dot
                let dotRect = CGRect(
                    x: position.x - radius,
                    y: position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Circle().path(in: dotRect), with: .color(dotColor))
            }
        }
    }

    private func positionForPoint(
        _ point: DisplayViewModel.GraphPoint,
        in size: CGSize,
        xBounds: ClosedRange<TimeInterval>,
        yBounds: ClosedRange<Double>
    ) -> CGPoint {
        let xRange = max(0.001, xBounds.upperBound - xBounds.lowerBound)
        let yRange = max(0.001, yBounds.upperBound - yBounds.lowerBound)

        let timestamp = point.timestamp.timeIntervalSinceReferenceDate
        let normalizedX = (timestamp - xBounds.lowerBound) / xRange
        let normalizedY = (point.latencyMS - yBounds.lowerBound) / yRange

        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)

        let drawWidth = size.width - plotPadding * 2
        let drawHeight = size.height - plotPadding * 2

        return CGPoint(
            x: plotPadding + clampedX * drawWidth,
            y: plotPadding + (1 - clampedY) * drawHeight
        )
    }

    private func dateBounds(_ points: [DisplayViewModel.GraphPoint]) -> ClosedRange<TimeInterval> {
        let values = points.map { $0.timestamp.timeIntervalSinceReferenceDate }
        guard let lower = values.min(), let upper = values.max() else {
            return 0 ... 1
        }

        if lower == upper {
            return (lower - 1) ... (upper + 1)
        }

        return lower ... upper
    }

    private func latencyBounds(_ points: [DisplayViewModel.GraphPoint]) -> ClosedRange<Double> {
        let values = points.map(\.latencyMS)
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0 ... 100
        }

        // Use a "nice" tick step (1/2/2.5/5 * 10^n) based on the visible data.
        // This avoids jumping from ~1000ms to a 2000ms axis ceiling just to keep
        // the top label "round".
        let range = max(0.001, maxVal - minVal)
        let rawStep = range / Double(max(1, gridLineCount))
        let step = max(1, niceNumber(rawStep, round: true))

        var lower = floor(minVal / step) * step
        var upper = ceil(maxVal / step) * step

        if lower == upper {
            upper = lower + step
        }

        lower = max(0, lower)
        upper = max(lower + step, upper)

        return lower ... upper
    }

    private func niceNumber(_ x: Double, round: Bool) -> Double {
        guard x > 0 else { return 1 }

        let exp = floor(log10(x))
        let f = x / pow(10, exp)

        let nf: Double
        if round {
            if f < 1.5 {
                nf = 1
            } else if f < 2.25 {
                nf = 2
            } else if f < 3.5 {
                nf = 2.5
            } else if f < 7.5 {
                nf = 5
            } else {
                nf = 10
            }
        } else {
            if f <= 1 {
                nf = 1
            } else if f <= 2 {
                nf = 2
            } else if f <= 2.5 {
                nf = 2.5
            } else if f <= 5 {
                nf = 5
            } else {
                nf = 10
            }
        }

        return nf * pow(10, exp)
    }
}

#if DEBUG
struct DisplayGraphView_Previews: PreviewProvider {
    static var previews: some View {
        DisplayGraphView(points: [
            .init(timestamp: .init(timeIntervalSinceNow: -50), latencyMS: 12),
            .init(timestamp: .init(timeIntervalSinceNow: -45), latencyMS: 85),
            .init(timestamp: .init(timeIntervalSinceNow: -40), latencyMS: 120),
            .init(timestamp: .init(timeIntervalSinceNow: -35), latencyMS: 45),
            .init(timestamp: .init(timeIntervalSinceNow: -30), latencyMS: 153),
            .init(timestamp: .init(timeIntervalSinceNow: -25), latencyMS: 28),
            .init(timestamp: .init(timeIntervalSinceNow: -20), latencyMS: 15),
            .init(timestamp: .init(timeIntervalSinceNow: -15), latencyMS: 22),
            .init(timestamp: .init(timeIntervalSinceNow: -10), latencyMS: 18),
            .init(timestamp: .init(timeIntervalSinceNow: -5), latencyMS: 25),
            .init(timestamp: .init(timeIntervalSinceNow: 0), latencyMS: 19)
        ])
        .padding()
        .frame(width: 320, height: 160)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
