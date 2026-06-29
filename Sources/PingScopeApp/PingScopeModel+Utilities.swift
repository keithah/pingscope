import Foundation
@preconcurrency import Network
import PingScopeCore

extension PingScopeModel {
    nonisolated static func networkStatus(from path: NWPath) -> NetworkConnectivityStatus {
        switch path.status {
        case .satisfied:
            .connected
        case .requiresConnection:
            .noInternet
        case .unsatisfied:
            path.availableInterfaces.isEmpty ? .notConnected : .noIPAddress
        @unknown default:
            .notConnected
        }
    }

    nonisolated static func networkPathSignature(from path: NWPath) -> String {
        let interfaces = path.availableInterfaces
            .map { "\($0.type)-\($0.name)" }
            .sorted()
            .joined(separator: ",")
        return "\(path.status)|\(path.isExpensive)|\(path.isConstrained)|\(interfaces)"
    }

    static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "PingScope-History" : cleaned
    }
}
