import Foundation
import PingScopeCore

public enum HistoryLens: String, CaseIterable, Codable, Hashable, Sendable {
    case chart
    case map

    public static let defaultValue: Self = .chart
}

public enum HistoryMapLens: String, CaseIterable, Codable, Hashable, Sendable {
    case pins
    case heat

    public static func defaultValue(for range: HistoryRange) -> Self {
        range.usesLongRangeReduction ? .heat : .pins
    }

    public static func effective(for range: HistoryRange, override: Self?) -> Self {
        override ?? defaultValue(for: range)
    }
}

public enum HistoryMapQuality: Int, CaseIterable, Codable, Comparable, Sendable {
    case fast
    case moderate
    case slow
    case failure

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct HistoryMapPoint: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let latencyMilliseconds: Double?
    public let isSuccess: Bool
    public let quality: HistoryMapQuality
    public let horizontalAccuracy: Double?
    public let networkName: String?
    public let networkInterface: String?

    fileprivate init(sample: PingResult, location: SampleLocation) {
        id = sample.id
        latitude = location.latitude
        longitude = location.longitude
        timestamp = sample.timestamp
        let finiteLatency = sample.latency.map(\.milliseconds).flatMap { $0.isFinite ? $0 : nil }
        latencyMilliseconds = finiteLatency
        isSuccess = sample.isSuccess
        horizontalAccuracy = location.horizontalAccuracy
        networkName = location.networkName
        networkInterface = location.networkInterface
        if !sample.isSuccess {
            quality = .failure
        } else if let finiteLatency, finiteLatency < 30 {
            quality = .fast
        } else if let finiteLatency, finiteLatency <= 80 {
            quality = .moderate
        } else {
            quality = .slow
        }
    }
}

public struct HistoryMapRoutePoint: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date

    fileprivate init(point: HistoryMapPoint) {
        id = point.id
        latitude = point.latitude
        longitude = point.longitude
        timestamp = point.timestamp
    }
}

public struct HistoryMapPointDetailPresentation: Equatable, Sendable {
    public let readingText: String
    public let outcomeText: String
    public let networkName: String?
    public let networkInterface: String?
    public let timestamp: Date
    public let horizontalAccuracyText: String?

    public var accessibilitySummary: String {
        [
            readingText,
            outcomeText,
            networkName.map { "Network, \($0)" },
            networkInterface.map { "Interface, \($0)" },
            "Time, \(timestamp.formatted(date: .abbreviated, time: .shortened))",
            horizontalAccuracyText.map { "Accuracy, \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    public init(point: HistoryMapPoint) {
        let readingText: String
        let outcomeText: String
        if point.isSuccess, let latency = point.latencyMilliseconds {
            readingText = "\(Int(latency.rounded())) ms"
            outcomeText = "Success"
        } else {
            readingText = "Failed"
            outcomeText = "Failure"
        }

        let accuracyText = point.horizontalAccuracy.map { "±\(Int($0.rounded())) m" }
        self.readingText = readingText
        self.outcomeText = outcomeText
        self.networkName = point.networkName
        self.networkInterface = point.networkInterface
        self.timestamp = point.timestamp
        self.horizontalAccuracyText = accuracyText
    }
}

public struct HistoryMapWorstZonePresentation: Equatable, Sendable {
    public let readingText: String
    public let outcomeText: String
    public let accessibilitySummary: String

    public init(point: HistoryMapPoint) {
        if point.isSuccess, let latency = point.latencyMilliseconds {
            readingText = "\(Int(latency.rounded())) ms"
            outcomeText = "Success"
        } else {
            readingText = "Failed"
            outcomeText = "Failure"
        }
        accessibilitySummary = "Worst zone, \(readingText), \(outcomeText)"
    }
}

public struct HistoryMapSummary: Equatable, Sendable {
    public let bestLatencyMilliseconds: Double?
    public let worstLatencyMilliseconds: Double?
    public let networkLabels: [String]
    public let worstRenderedPoint: HistoryMapPoint?
}

public struct HistoryMapPresentation: Equatable, Sendable {
    public static let defaultMaximumPointCount = 500
    public static let defaultMaximumRoutePointCount = 500

    public let points: [HistoryMapPoint]
    public let route: [HistoryMapRoutePoint]
    public let summary: HistoryMapSummary

    public init(
        samples: [PingResult],
        maximumPointCount: Int = defaultMaximumPointCount,
        maximumRoutePointCount: Int = defaultMaximumRoutePointCount
    ) {
        let located = samples.compactMap { sample -> HistoryMapPoint? in
            guard let location = sample.location,
                  location.latitude.isFinite,
                  location.longitude.isFinite,
                  (-90...90).contains(location.latitude),
                  (-180...180).contains(location.longitude) else { return nil }
            return HistoryMapPoint(sample: sample, location: location)
        }
        let chronological = Self.chronological(located)
        points = Self.spatialReduction(chronological, limit: maximumPointCount)
        route = Self.routeReduction(chronological, limit: maximumRoutePointCount)

        let successfulLatencies = chronological.compactMap { point -> Double? in
            guard point.isSuccess else { return nil }
            return point.latencyMilliseconds
        }
        let networkLabels = Set(chronological.compactMap(Self.networkLabel))
        summary = HistoryMapSummary(
            bestLatencyMilliseconds: successfulLatencies.min(),
            worstLatencyMilliseconds: successfulLatencies.max(),
            networkLabels: networkLabels.sorted(),
            worstRenderedPoint: points.max(by: Self.isLessSevere)
        )
    }

    private struct GridCell: Hashable {
        let row: Int
        let column: Int
    }

    private static func chronological(_ points: [HistoryMapPoint]) -> [HistoryMapPoint] {
        points.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func spatialReduction(
        _ points: [HistoryMapPoint],
        limit: Int
    ) -> [HistoryMapPoint] {
        guard limit > 0, !points.isEmpty else { return [] }
        guard points.count > limit else { return points }

        let latitudes = points.map(\.latitude)
        let unwrappedLongitudes = unwrapLongitudes(points.map(\.longitude))
        let minimumLatitude = latitudes.min()!
        let maximumLatitude = latitudes.max()!
        let minimumLongitude = unwrappedLongitudes.min()!
        let maximumLongitude = unwrappedLongitudes.max()!
        let latitudeSpan = maximumLatitude - minimumLatitude
        let longitudeSpan = maximumLongitude - minimumLongitude
        let middleLatitude = (minimumLatitude + maximumLatitude) / 2
        let scaledLongitudeSpan = longitudeSpan * max(0.01, cos(middleLatitude * .pi / 180))
        let dimensions = gridDimensions(
            latitudeSpan: latitudeSpan,
            longitudeSpan: scaledLongitudeSpan,
            limit: limit
        )

        var representatives: [GridCell: HistoryMapPoint] = [:]
        for (index, point) in points.enumerated() {
            let row = gridIndex(
                value: point.latitude,
                minimum: minimumLatitude,
                span: latitudeSpan,
                count: dimensions.rows
            )
            let column = gridIndex(
                value: unwrappedLongitudes[index],
                minimum: minimumLongitude,
                span: longitudeSpan,
                count: dimensions.columns
            )
            let cell = GridCell(row: row, column: column)
            if let current = representatives[cell] {
                if isLessSevere(current, point) {
                    representatives[cell] = point
                }
            } else {
                representatives[cell] = point
            }
        }
        return chronological(Array(representatives.values))
    }

    private static func gridDimensions(
        latitudeSpan: Double,
        longitudeSpan: Double,
        limit: Int
    ) -> (rows: Int, columns: Int) {
        if latitudeSpan == 0, longitudeSpan == 0 { return (1, 1) }
        if latitudeSpan == 0 { return (1, limit) }
        if longitudeSpan == 0 { return (limit, 1) }

        let limitAsDouble = Double(limit)
        if longitudeSpan >= latitudeSpan * limitAsDouble { return (1, limit) }
        if latitudeSpan >= longitudeSpan * limitAsDouble { return (limit, 1) }

        let aspect = longitudeSpan / latitudeSpan
        let columns = min(limit, max(1, Int(sqrt(limitAsDouble * aspect).rounded(.down))))
        let rows = max(1, limit / columns)
        return (rows, columns)
    }

    private static func gridIndex(value: Double, minimum: Double, span: Double, count: Int) -> Int {
        guard count > 1, span > 0 else { return 0 }
        return min(count - 1, max(0, Int(((value - minimum) / span) * Double(count))))
    }

    private static func unwrapLongitudes(_ longitudes: [Double]) -> [Double] {
        guard longitudes.count > 1 else { return longitudes }
        let normalized = longitudes.map { longitude -> Double in
            let value = longitude.truncatingRemainder(dividingBy: 360)
            return value < 0 ? value + 360 : value
        }
        let sorted = normalized.sorted()
        var largestGap = -Double.infinity
        var origin = sorted[0]
        for index in sorted.indices {
            let nextIndex = (index + 1) % sorted.count
            let next = nextIndex == 0 ? sorted[0] + 360 : sorted[nextIndex]
            let gap = next - sorted[index]
            if gap > largestGap {
                largestGap = gap
                origin = next.truncatingRemainder(dividingBy: 360)
            }
        }
        return normalized.map { value in
            let delta = value - origin
            return delta < 0 ? delta + 360 : delta
        }
    }

    private static func routeReduction(
        _ points: [HistoryMapPoint],
        limit: Int
    ) -> [HistoryMapRoutePoint] {
        guard limit > 0 else { return [] }
        let unique = points.reduce(into: [HistoryMapPoint]()) { result, point in
            guard result.last?.latitude != point.latitude || result.last?.longitude != point.longitude else {
                return
            }
            result.append(point)
        }
        guard unique.count > limit else { return unique.map(HistoryMapRoutePoint.init) }
        guard limit > 1 else { return [HistoryMapRoutePoint(point: unique[0])] }
        return (0..<limit).map { index in
            let sourceIndex = index * (unique.count - 1) / (limit - 1)
            return HistoryMapRoutePoint(point: unique[sourceIndex])
        }
    }

    private static func networkLabel(_ point: HistoryMapPoint) -> String? {
        if let name = nonempty(point.networkName) { return name }
        return nonempty(point.networkInterface)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isLessSevere(_ lhs: HistoryMapPoint, _ rhs: HistoryMapPoint) -> Bool {
        if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
        let lhsLatency = lhs.latencyMilliseconds ?? (lhs.isSuccess ? .infinity : 0)
        let rhsLatency = rhs.latencyMilliseconds ?? (rhs.isSuccess ? .infinity : 0)
        if lhsLatency != rhsLatency { return lhsLatency < rhsLatency }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
