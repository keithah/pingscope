import Foundation

public enum PingScopeExtensionControlKind {
    public static let monitoring = "com.hadm.pingscope.monitoring-control"
    public static let status = "com.hadm.pingscope.status-control"
}

public struct PingScopeExtensionControlStateProjection: Sendable {
    public let isMonitoring: Bool
    public let statusText: String
    public let symbolName: String

    public init(isMonitoring: Bool, statusText: String, symbolName: String) {
        self.isMonitoring = isMonitoring
        self.statusText = statusText
        self.symbolName = symbolName
    }

    public static func load() -> Self {
        let defaults = UserDefaults(suiteName: "group.com.hadm.pingscope")
        let data = defaults?.data(forKey: "PingScopeWidgetSnapshot")
        let monitoring = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0).monitoring?.isActive } ?? false
        return .init(
            isMonitoring: monitoring,
            statusText: monitoring ? "Monitoring On" : "Monitoring Off",
            symbolName: monitoring ? "wave.3.right.circle.fill" : "wave.3.right.circle"
        )
    }

    private struct Snapshot: Decodable {
        let monitoring: Monitoring?
        struct Monitoring: Decodable { let isActive: Bool }
    }
}

public enum PingScopeExtensionIntentRequest: Codable, Sendable { case start; case stop }

public final class PingScopeExtensionIntentCommandStore: @unchecked Sendable {
    public init() {}
    public func enqueue(_ request: PingScopeExtensionIntentRequest) -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.hadm.pingscope"),
              let data = try? JSONEncoder().encode(request) else { return false }
        defaults.set(data, forKey: "PingScope.iOS.pendingIntentCommand")
        return true
    }
}
