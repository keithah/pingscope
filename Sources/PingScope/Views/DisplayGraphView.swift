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
            .fill(Color.black.opacity(0.3))
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
            // Dark background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))

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
            let lineColor = Color.white.opacity(0.1)

            // Horizontal grid lines
            for value in yValues {
                let normalizedY = (value - yBounds.lowerBound) / max(0.001, yBounds.upperBound - yBounds.lowerBound)
                let y = (1 - normalizedY) * canvasSize.height

                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))

                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }

            // Vertical grid lines (4 segments)
            let verticalCount = 4
            for i in 1..<verticalCount {
                let x = canvasSize.width * CGFloat(i) / CGFloat(verticalCount)

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))

                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
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
        guard let maxVal = values.max() else {
            return 0 ... 100
        }

        // Always start from 0 and round up to nice number
        let niceMax = ceilToNice(maxVal * 1.1)
        return 0 ... niceMax
    }

    private func ceilToNice(_ value: Double) -> Double {
        if value <= 0 { return 100 }

        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude

        let niceNormalized: Double
        if normalized <= 1 {
            niceNormalized = 1
        } else if normalized <= 2 {
            niceNormalized = 2
        } else if normalized <= 5 {
            niceNormalized = 5
        } else {
            niceNormalized = 10
        }

        return niceNormalized * magnitude
    }
}

#Preview {
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
