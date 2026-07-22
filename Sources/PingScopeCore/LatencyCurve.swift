import CoreGraphics
#if DEBUG
import os

private let latencyCurvePointsOfInterestLog = OSLog(
    subsystem: "tv.kodi.pingscope",
    category: .pointsOfInterest
)
#endif

public enum LatencyCurve {
    public static func smoothedPath(points: [CGPoint], closed: Bool) -> CGPath {
        #if DEBUG
        let signpostID = OSSignpostID(log: latencyCurvePointsOfInterestLog)
        os_signpost(
            .begin,
            log: latencyCurvePointsOfInterestLog,
            name: "LatencyCurve.smoothedPath",
            signpostID: signpostID
        )
        defer {
            os_signpost(
                .end,
                log: latencyCurvePointsOfInterestLog,
                name: "LatencyCurve.smoothedPath",
                signpostID: signpostID
            )
        }
        #endif
        let path = CGMutablePath()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            if closed {
                path.closeSubpath()
            }
            return path
        }
        guard points.count > 2 else {
            path.addLine(to: points[1])
            if closed {
                path.closeSubpath()
            }
            return path
        }

        let minimumY = points.map(\.y).min() ?? first.y
        let maximumY = points.map(\.y).max() ?? first.y

        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : extrapolatedPoint(before: points[index], next: points[index + 1])
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : extrapolatedPoint(after: p2, previous: p1)

            let controls = cubicControls(
                p0: p0,
                p1: p1,
                p2: p2,
                p3: p3,
                minimumY: minimumY,
                maximumY: maximumY
            )
            path.addCurve(to: p2, control1: controls.control1, control2: controls.control2)
        }

        if closed {
            path.closeSubpath()
        }
        return path
    }

    private static func cubicControls(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        minimumY: CGFloat,
        maximumY: CGFloat
    ) -> (control1: CGPoint, control2: CGPoint) {
        let t0: CGFloat = 0
        let t1 = nextParameter(after: t0, from: p0, to: p1)
        let t2 = nextParameter(after: t1, from: p1, to: p2)
        let t3 = nextParameter(after: t2, from: p2, to: p3)
        let segmentDuration = max(t2 - t1, .ulpOfOne)

        let tangent1 = vector(from: p0, to: p2, duration: max(t2 - t0, .ulpOfOne))
        let tangent2 = vector(from: p1, to: p3, duration: max(t3 - t1, .ulpOfOne))

        var control1 = CGPoint(
            x: p1.x + tangent1.dx * segmentDuration / 3,
            y: p1.y + tangent1.dy * segmentDuration / 3
        )
        var control2 = CGPoint(
            x: p2.x - tangent2.dx * segmentDuration / 3,
            y: p2.y - tangent2.dy * segmentDuration / 3
        )

        let minX = min(p1.x, p2.x)
        let maxX = max(p1.x, p2.x)
        control1.x = control1.x.clamped(to: minX...maxX)
        control2.x = control2.x.clamped(to: minX...maxX)
        control1.y = control1.y.clamped(to: minimumY...maximumY)
        control2.y = control2.y.clamped(to: minimumY...maximumY)
        return (control1, control2)
    }

    private static func nextParameter(after t: CGFloat, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        return t + max(sqrt(distance), .ulpOfOne)
    }

    private static func vector(from start: CGPoint, to end: CGPoint, duration: CGFloat) -> CGVector {
        CGVector(dx: (end.x - start.x) / duration, dy: (end.y - start.y) / duration)
    }

    private static func extrapolatedPoint(before point: CGPoint, next: CGPoint) -> CGPoint {
        CGPoint(x: point.x - (next.x - point.x), y: point.y - (next.y - point.y))
    }

    private static func extrapolatedPoint(after point: CGPoint, previous: CGPoint) -> CGPoint {
        CGPoint(x: point.x + (point.x - previous.x), y: point.y + (point.y - previous.y))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
