import Foundation

enum PingMethod: String, Sendable, Codable, CaseIterable, Equatable {
    case tcp
    case udp
    case icmpSimulated

    // ICMP-simulated mode attempts TCP probes in this order.
    static let icmpSimulatedProbePorts: [UInt16] = [53, 80, 443, 22, 25]

    var displayName: String {
        switch self {
        case .tcp:
            return "TCP"
        case .udp:
            return "UDP"
        case .icmpSimulated:
            return "ICMP (Simulated)"
        }
    }

    var defaultPort: UInt16 {
        switch self {
        case .tcp:
            return 80
        case .udp:
            return 53
        case .icmpSimulated:
            return 53
        }
    }
}
