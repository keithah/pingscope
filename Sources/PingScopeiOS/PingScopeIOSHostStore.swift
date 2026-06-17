import Foundation
import PingScopeCore

public struct PingScopeIOSHostState: Equatable, Sendable {
    public var hosts: [HostConfig]
    public var selectedHost: HostConfig

    public init(hosts: [HostConfig], selectedHost: HostConfig) {
        self.hosts = hosts
        self.selectedHost = selectedHost
    }
}

public final class PingScopeIOSHostStore: @unchecked Sendable {
    public static let defaultHosts: [HostConfig] = [
        HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1"),
        HostConfig(displayName: "Google DNS", address: "8.8.8.8")
    ]

    private let defaults: UserDefaults
    private let defaultHosts: [HostConfig]
    private let hostsKey = "PingScope.iOS.hosts"
    private let selectedHostIDKey = "PingScope.iOS.selectedHostID"

    public init(defaults: UserDefaults = .standard, defaultHosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts) {
        self.defaults = defaults
        self.defaultHosts = defaultHosts.isEmpty ? [HostConfig.defaultInternet] : defaultHosts
    }

    public func load() -> PingScopeIOSHostState {
        let hosts = loadHosts()
        let selectedID = defaults.string(forKey: selectedHostIDKey).flatMap(UUID.init(uuidString:))
        let selectedHost = selectedID.flatMap { id in
            hosts.first { $0.id == id }
        } ?? hosts[0]
        return PingScopeIOSHostState(hosts: hosts, selectedHost: selectedHost)
    }

    public func save(hosts: [HostConfig], selectedHostID: UUID) {
        let normalizedHosts = hosts.isEmpty ? defaultHosts : hosts
        if let data = try? JSONEncoder().encode(normalizedHosts) {
            defaults.set(data, forKey: hostsKey)
        }
        defaults.set(selectedHostID.uuidString, forKey: selectedHostIDKey)
    }

    private func loadHosts() -> [HostConfig] {
        guard
            let data = defaults.data(forKey: hostsKey),
            let hosts = try? JSONDecoder().decode([HostConfig].self, from: data),
            !hosts.isEmpty
        else {
            return defaultHosts
        }
        return hosts
    }
}
