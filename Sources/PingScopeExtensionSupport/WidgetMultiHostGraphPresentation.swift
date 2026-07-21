import Foundation

public struct WidgetGraphRGB: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct WidgetGraphDisplayColor: Codable, Equatable, Sendable {
    public let light: WidgetGraphRGB
    public let dark: WidgetGraphRGB

    public init(light: WidgetGraphRGB, dark: WidgetGraphRGB) {
        self.light = light
        self.dark = dark
    }

    public static func automatic(for hostID: UUID) -> WidgetGraphDisplayColor {
        let light: [(UInt8, UInt8, UInt8)] = [
            (0x00, 0x68, 0xD9), (0xD9, 0x1D, 0x5B), (0x00, 0x8C, 0x78),
            (0x6D, 0x28, 0xD9), (0xB7, 0x79, 0x00), (0xD9, 0x5F, 0x00),
            (0x00, 0x83, 0x5D), (0x8C, 0x22, 0xC7), (0x00, 0x77, 0xB6),
            (0xC9, 0x1E, 0x3A), (0x56, 0x8A, 0x00), (0xA8, 0x5D, 0x00),
        ]
        let dark: [(UInt8, UInt8, UInt8)] = [
            (0x27, 0x8D, 0xFF), (0xFF, 0x3D, 0x7F), (0x00, 0xD1, 0xB2),
            (0x9B, 0x6C, 0xFF), (0xFF, 0xC4, 0x00), (0xFF, 0x8A, 0x00),
            (0x00, 0xC8, 0x96), (0xC5, 0x4C, 0xFF), (0x00, 0xB8, 0xF5),
            (0xFF, 0x45, 0x60), (0x8F, 0xD4, 0x00), (0xEF, 0xA3, 0x3A),
        ]
        let bytes = hostID.uuid
        let hash = [
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15,
        ].reduce(UInt64.zero) { partialResult, byte in
            (partialResult &* 31) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(light.count))
        return WidgetGraphDisplayColor(
            light: rgb(light[index]),
            dark: rgb(dark[index])
        )
    }

    private static func rgb(_ value: (UInt8, UInt8, UInt8)) -> WidgetGraphRGB {
        WidgetGraphRGB(
            red: Double(value.0) / 255,
            green: Double(value.1) / 255,
            blue: Double(value.2) / 255
        )
    }
}

public struct WidgetGraphHost: Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let displayColor: WidgetGraphDisplayColor?

    public init(id: UUID, displayName: String, displayColor: WidgetGraphDisplayColor? = nil) {
        self.id = id
        self.displayName = displayName
        self.displayColor = displayColor ?? .automatic(for: id)
    }
}

public struct WidgetGraphSample: Equatable, Sendable {
    public let id: UUID
    public let hostID: UUID
    public let timestamp: Date
    public let latencyMilliseconds: Double?

    public init(id: UUID, hostID: UUID, timestamp: Date, latencyMilliseconds: Double?) {
        self.id = id
        self.hostID = hostID
        self.timestamp = timestamp
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct WidgetMultiHostGraphPresentation: Equatable, Sendable {
    public struct LegendEntry: Equatable, Sendable {
        public let hostID: UUID
        public let displayName: String
        public let displayColor: WidgetGraphDisplayColor?
    }

    public struct Series: Equatable, Sendable {
        public let hostID: UUID
        public let samples: [WidgetGraphSample]
        public let pathPoints: [WidgetGraphSample]
        public let displayColor: WidgetGraphDisplayColor?
    }

    public struct TimeWindow: Equatable, Sendable {
        public let start: Date
        public let end: Date
    }

    public struct LatencyScale: Equatable, Sendable {
        public let minimumMilliseconds: Double
        public let maximumMilliseconds: Double
    }

    public let legend: [LegendEntry]
    public let series: [Series]
    public let timeWindow: TimeWindow?
    public let latencyScale: LatencyScale?

    public init(hosts: [WidgetGraphHost], samples: [WidgetGraphSample]) {
        let visibleHosts = WidgetHostSelection(hosts: hosts).visibleHosts(maximum: 5)
        let visibleHostIDs = Set(visibleHosts.map(\.id))
        let visibleSamples = samples.filter { visibleHostIDs.contains($0.hostID) }
        legend = visibleHosts.map {
            LegendEntry(hostID: $0.id, displayName: $0.displayName, displayColor: $0.displayColor)
        }
        series = visibleHosts.map { host in
            let hostSamples = visibleSamples.filter { $0.hostID == host.id }
            return Series(
                hostID: host.id,
                samples: hostSamples,
                pathPoints: hostSamples.filter { $0.latencyMilliseconds != nil },
                displayColor: host.displayColor
            )
        }
        if let start = visibleSamples.map(\.timestamp).min(), let end = visibleSamples.map(\.timestamp).max() {
            timeWindow = TimeWindow(start: start, end: end)
        } else {
            timeWindow = nil
        }
        let latencies = visibleSamples.compactMap(\.latencyMilliseconds)
        if let minimum = latencies.min(), let maximum = latencies.max() {
            latencyScale = LatencyScale(minimumMilliseconds: minimum, maximumMilliseconds: maximum)
        } else {
            latencyScale = nil
        }
    }
}

public struct WidgetHostSelection: Equatable, Sendable {
    public let hosts: [WidgetGraphHost]

    public init(hosts: [WidgetGraphHost]) {
        self.hosts = hosts
    }

    public func visibleHosts(maximum: Int = 5) -> [WidgetGraphHost] {
        Array(hosts.prefix(max(maximum, 0)))
    }
}
