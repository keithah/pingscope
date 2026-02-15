import Foundation

enum AlertType: String, Codable, CaseIterable, Sendable {
    case noResponse
    case highLatency
    case recovery
    case degradation
    case intermittent
    case networkChange
    case internetLoss

    var displayName: String {
        switch self {
        case .noResponse:
            return "No Response"
        case .highLatency:
            return "High Latency"
        case .recovery:
            return "Recovery"
        case .degradation:
            return "Degradation"
        case .intermittent:
            return "Intermittent Failures"
        case .networkChange:
            return "Network Change"
        case .internetLoss:
            return "Internet Loss"
        }
    }
}
