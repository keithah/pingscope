import Foundation

public struct HistoryMapExportCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct HistoryMapExportPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct HistoryMapExportRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        minX = min(x, x + width)
        minY = min(y, y + height)
        maxX = max(x, x + width)
        maxY = max(y, y + height)
    }

    public func contains(_ point: HistoryMapExportPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

public enum HistoryMapExportFailureCue: Equatable, Sendable {
    case none
    case octagonCross
}

public struct HistoryMapExportRoutePoint: Equatable, Sendable {
    public let position: HistoryMapExportPoint
}

public struct HistoryMapExportPin: Equatable, Sendable {
    public let position: HistoryMapExportPoint
    public let quality: HistoryMapQuality
    public let failureCue: HistoryMapExportFailureCue
}

public struct HistoryMapExportCircle: Equatable, Sendable {
    public let center: HistoryMapExportPoint
    public let radiusMeters: Double
    public let quality: HistoryMapQuality
    public let opacity: Double
    public let failureCue: HistoryMapExportFailureCue
}

/// A deterministic platform-neutral drawing description. The projection seam
/// is supplied by the visible map snapshot. Route segments are clipped against
/// its viewport while pins/circles outside it are omitted.
public struct HistoryMapDrawingPlan: Equatable, Sendable {
    public let lens: HistoryMapLens
    public let routeSegments: [[HistoryMapExportRoutePoint]]
    public let points: [HistoryMapExportPin]
    public let circles: [HistoryMapExportCircle]

    public init(
        presentation: HistoryMapPresentation,
        lens: HistoryMapLens,
        viewport: HistoryMapExportRect,
        project: (HistoryMapExportCoordinate) -> HistoryMapExportPoint
    ) {
        self.lens = lens
        switch lens {
        case .pins:
            let projectedRoute = presentation.route.prefix(HistoryMapPresentation.defaultMaximumRoutePointCount).map {
                project(.init(latitude: $0.latitude, longitude: $0.longitude))
            }
            routeSegments = Self.clippedRouteSegments(
                projectedRoute,
                viewport: viewport,
                maximumPointCount: HistoryMapPresentation.defaultMaximumRoutePointCount
            )
            points = presentation.points.prefix(HistoryMapPresentation.defaultMaximumPointCount).compactMap { point in
                let position = project(.init(latitude: point.latitude, longitude: point.longitude))
                guard viewport.contains(position) else { return nil }
                return HistoryMapExportPin(
                    position: position,
                    quality: point.quality,
                    failureCue: point.quality == .failure ? .octagonCross : .none
                )
            }
            circles = []
        case .heat:
            routeSegments = []
            points = []
            circles = presentation.points.prefix(HistoryMapPresentation.defaultMaximumPointCount).compactMap { point in
                let center = project(.init(latitude: point.latitude, longitude: point.longitude))
                guard viewport.contains(center) else { return nil }
                return HistoryMapExportCircle(
                    center: center,
                    radiusMeters: max(75, point.horizontalAccuracy ?? 100),
                    quality: point.quality,
                    opacity: 0.26,
                    failureCue: point.quality == .failure ? .octagonCross : .none
                )
            }
        }
    }

    private static func clippedRouteSegments(
        _ route: [HistoryMapExportPoint],
        viewport: HistoryMapExportRect,
        maximumPointCount: Int
    ) -> [[HistoryMapExportRoutePoint]] {
        guard route.count > 1, maximumPointCount > 1 else { return [] }
        var result: [[HistoryMapExportRoutePoint]] = []
        var current: [HistoryMapExportRoutePoint] = []

        func finishCurrent() {
            if current.count > 1 { result.append(current) }
            current = []
        }

        for index in 1..<route.count {
            guard let clipped = clip(route[index - 1], route[index], to: viewport) else {
                finishCurrent()
                continue
            }
            let start = HistoryMapExportRoutePoint(position: clipped.0)
            let end = HistoryMapExportRoutePoint(position: clipped.1)
            if current.last == start {
                if current.last != end { current.append(end) }
            } else {
                finishCurrent()
                current = start == end ? [] : [start, end]
            }
        }
        finishCurrent()

        var remaining = maximumPointCount
        return result.compactMap { segment in
            guard remaining >= 2 else { return nil }
            let bounded = Array(segment.prefix(remaining))
            remaining -= bounded.count
            return bounded.count > 1 ? bounded : nil
        }
    }

    /// Liang-Barsky line clipping retains crossing segments even when neither
    /// endpoint is visible and gives deterministic break points at the viewport.
    private static func clip(
        _ start: HistoryMapExportPoint,
        _ end: HistoryMapExportPoint,
        to rect: HistoryMapExportRect
    ) -> (HistoryMapExportPoint, HistoryMapExportPoint)? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let values = [
            (-dx, start.x - rect.minX),
            (dx, rect.maxX - start.x),
            (-dy, start.y - rect.minY),
            (dy, rect.maxY - start.y),
        ]
        var lower = 0.0
        var upper = 1.0
        for (direction, distance) in values {
            if direction == 0 {
                if distance < 0 { return nil }
                continue
            }
            let ratio = distance / direction
            if direction < 0 {
                lower = max(lower, ratio)
            } else {
                upper = min(upper, ratio)
            }
            if lower > upper { return nil }
        }
        return (
            .init(x: start.x + lower * dx, y: start.y + lower * dy),
            .init(x: start.x + upper * dx, y: start.y + upper * dy)
        )
    }
}
