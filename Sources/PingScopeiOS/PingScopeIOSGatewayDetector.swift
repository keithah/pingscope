import Foundation
import PingScopeCore

#if os(iOS)
import Darwin
#endif

public struct PingScopeIOSGatewayDetector: Sendable {
    public init() {}

    public func detect() async -> HostConfig? {
        guard let address = Self.likelyGatewayAddress() else { return nil }
        return DefaultGatewayDetector.gatewayHost(address: address)
    }

    public static func likelyGatewayAddress(fromIPv4Address address: String) -> String? {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }

        let isPrivateOrLinkLocal =
            octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)

        guard isPrivateOrLinkLocal, octets[3] != 1 else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).1"
    }

    public static func likelyGatewayAddress() -> String? {
        #if os(iOS)
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return nil
        }
        defer { freeifaddrs(interfaceAddresses) }

        var candidates: [(priority: Int, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addressPointer = interface.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            var socketAddress = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &socketAddress.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }

            let interfaceAddress = String(cString: buffer)
            guard let gatewayAddress = likelyGatewayAddress(fromIPv4Address: interfaceAddress) else {
                continue
            }

            let priority = name.hasPrefix("en") ? 0 : name.hasPrefix("pdp_ip") ? 1 : 2
            candidates.append((priority, gatewayAddress))
        }

        return candidates.min { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.address < rhs.address : lhs.priority < rhs.priority
        }?.address
        #else
        return nil
        #endif
    }
}
