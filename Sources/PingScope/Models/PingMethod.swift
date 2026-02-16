import Foundation

enum PingMethod: String, Sendable, Codable, CaseIterable, Equatable {
    case tcp
    case udp
    case icmp

    /// Returns the ping methods available in the current runtime environment.
    /// When running in App Store sandbox, true ICMP is not available.
    static var availableCases: [PingMethod] {
        if SandboxDetector.isRunningInSandbox {
            return [.tcp, .udp]
        }
        return allCases
    }

    var displayName: String {
        switch self {
        case .tcp:
            return "TCP"
        case .udp:
            return "UDP"
        case .icmp:
            return "ICMP"
        }
    }

    var defaultPort: UInt16 {
        switch self {
        case .tcp:
            return 80
        case .udp:
            return 53
        case .icmp:
            return 0
        }
    }
}
