import Foundation
import Network

/// Host configuration for ping monitoring
struct Host: Sendable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let port: UInt16
    let protocolType: ProtocolType
    let timeout: Duration
    let isDefault: Bool

    /// Protocol type for connection
    enum ProtocolType: String, Sendable, CaseIterable {
        case tcp
        case udp

        /// Convert to Network.framework NWParameters
        var parameters: NWParameters {
            switch self {
            case .tcp:
                return NWParameters.tcp
            case .udp:
                return NWParameters.udp
            }
        }
    }

    /// Create a new host with default values
    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: UInt16 = 443,
        protocolType: ProtocolType = .tcp,
        timeout: Duration = .seconds(3),
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.protocolType = protocolType
        self.timeout = timeout
        self.isDefault = isDefault
    }

    /// Google DNS default host
    static let googleDNS = Host(
        name: "Google DNS",
        address: "8.8.8.8",
        port: 443,
        protocolType: .tcp,
        isDefault: true
    )

    /// Cloudflare DNS default host
    static let cloudflareDNS = Host(
        name: "Cloudflare",
        address: "1.1.1.1",
        port: 443,
        protocolType: .tcp,
        isDefault: true
    )
}
