import Foundation

struct GlobalDefaults: Sendable, Codable, Equatable {
    var interval: Duration = .seconds(2)
    var timeout: Duration = .seconds(2)
    var greenThresholdMS: Double = 50.0
    var yellowThresholdMS: Double = 150.0
    var pingMethod: PingMethod = .tcp

    static let `default` = GlobalDefaults()

    enum CodingKeys: String, CodingKey {
        case intervalSeconds
        case timeoutSeconds
        case greenThresholdMS
        case yellowThresholdMS
        case pingMethod
    }

    init(
        interval: Duration = .seconds(2),
        timeout: Duration = .seconds(2),
        greenThresholdMS: Double = 50.0,
        yellowThresholdMS: Double = 150.0,
        pingMethod: PingMethod = .tcp
    ) {
        self.interval = interval
        self.timeout = timeout
        self.greenThresholdMS = greenThresholdMS
        self.yellowThresholdMS = yellowThresholdMS
        self.pingMethod = pingMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let intervalSeconds = try container.decode(TimeInterval.self, forKey: .intervalSeconds)
        let timeoutSeconds = try container.decode(TimeInterval.self, forKey: .timeoutSeconds)
        interval = .seconds(intervalSeconds)
        timeout = .seconds(timeoutSeconds)
        greenThresholdMS = try container.decode(Double.self, forKey: .greenThresholdMS)
        yellowThresholdMS = try container.decode(Double.self, forKey: .yellowThresholdMS)
        pingMethod = try container.decode(PingMethod.self, forKey: .pingMethod)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interval.timeInterval, forKey: .intervalSeconds)
        try container.encode(timeout.timeInterval, forKey: .timeoutSeconds)
        try container.encode(greenThresholdMS, forKey: .greenThresholdMS)
        try container.encode(yellowThresholdMS, forKey: .yellowThresholdMS)
        try container.encode(pingMethod, forKey: .pingMethod)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
