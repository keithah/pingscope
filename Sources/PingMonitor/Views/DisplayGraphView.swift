import SwiftUI

struct DisplayGraphView: View {
    let points: [DisplayViewModel.GraphPoint]

    var body: some View {
        GeometryReader { proxy in
            if points.isEmpty {
                emptyState
            } else {
                chart(in: proxy.size)
            }
        }
        .frame(minHeight: 96)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.secondary)
            .overlay {
                Text("No samples yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func chart(in size: CGSize) -> some View {
        let xBounds = dateBounds(points)
        let yBounds = latencyBounds(points)

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))

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
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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

        return CGPoint(
            x: clampedX * size.width,
            y: (1 - clampedY) * size.height
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
        guard let lower = values.min(), let upper = values.max() else {
            return 0 ... 1
        }

        if lower == upper {
            return max(0, lower - 1) ... (upper + 1)
        }

        return lower ... upper
    }
}

#Preview {
    DisplayGraphView(points: [
        .init(timestamp: .init(timeIntervalSinceNow: -20), latencyMS: 44),
        .init(timestamp: .init(timeIntervalSinceNow: -10), latencyMS: 51),
        .init(timestamp: .init(timeIntervalSinceNow: 0), latencyMS: 39)
    ])
    .padding()
    .frame(width: 280, height: 120)
}
