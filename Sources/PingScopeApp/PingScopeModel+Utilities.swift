import CoreLocation
import CoreWLAN
import Darwin
import Foundation
@preconcurrency import Network
import PingScopeCore
import Security

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

    nonisolated static func networkInterface(from path: NWPath) -> String {
        guard path.status == .satisfied else { return "other" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    nonisolated static func activeNetworkInterfaceNames() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(first) }

        var names: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let flags = Int32(interface.pointee.ifa_flags)
            if flags & IFF_UP != 0, let name = interface.pointee.ifa_name {
                names.append(String(cString: name))
            }
            current = interface.pointee.ifa_next
        }
        return names
    }

    static func currentWiFiName() -> String? {
        guard hasWiFiInfoEntitlement,
              CLLocationManager.locationServicesEnabled() else { return nil }
        guard CLLocationManager().authorizationStatus == .authorizedAlways else { return nil }
        return CWWiFiClient.shared().interface()?.ssid()
    }

    private static var hasWiFiInfoEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.networking.wifi-info" as CFString,
                  nil
              ) else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((value as! CFBoolean))
    }

    static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "PingScope-History" : cleaned
    }
}
