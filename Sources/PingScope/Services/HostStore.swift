import Foundation

actor HostStore {
    private let defaults: UserDefaults
    private let key: String = "pingmonitor.savedHosts"
    private let gatewayOverrideKey: String = "pingmonitor.gatewayHostOverride"

    private struct GatewayOverride: Codable {
        let address: String
        let pingMethod: PingMethod
        let port: UInt16
    }

    private(set) var hosts: [Host]
    private(set) var gatewayHost: Host?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedHosts = Self.loadHosts(from: defaults, key: key)
        let mergedHosts = Self.mergeDefaults(into: loadedHosts)
        self.hosts = mergedHosts
        self.gatewayHost = nil

        // Avoid calling actor-isolated methods from init (Swift 6 stricter isolation).
        if mergedHosts != loadedHosts {
            Self.persistHosts(mergedHosts, to: defaults, key: key)
        }
    }

    private func loadHosts() -> [Host] {
        Self.loadHosts(from: defaults, key: key)
    }

    private static func loadHosts(from defaults: UserDefaults, key: String) -> [Host] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([Host].self, from: data)
        } catch {
            return []
        }
    }

    private func persistHosts() {
        Self.persistHosts(hosts, to: defaults, key: key)
    }

    private static func persistHosts(_ hosts: [Host], to defaults: UserDefaults, key: String) {
        do {
            let data = try JSONEncoder().encode(hosts)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }

    func ensureDefaultsPresent() {
        if hosts.isEmpty {
            hosts = Host.defaults
            return
        }

        var merged = hosts
        let missingDefaults = Host.defaults.filter { defaultHost in
            !merged.contains { $0.isDefault && $0.name == defaultHost.name }
        }

        if !missingDefaults.isEmpty {
            merged.insert(contentsOf: missingDefaults, at: 0)
        }

        let defaultHosts = merged.filter(\.isDefault)
        let customHosts = merged.filter { !$0.isDefault }
        hosts = defaultHosts + customHosts
    }

    private static func mergeDefaults(into loadedHosts: [Host]) -> [Host] {
        guard !loadedHosts.isEmpty else {
            return Host.defaults
        }

        var merged = loadedHosts
        let missingDefaults = Host.defaults.filter { defaultHost in
            !merged.contains { $0.isDefault && $0.name == defaultHost.name }
        }

        if !missingDefaults.isEmpty {
            merged.insert(contentsOf: missingDefaults, at: 0)
        }

        // Keep defaults grouped at the top, mirroring ensureDefaultsPresent().
        let defaultHosts = merged.filter(\.isDefault)
        let customHosts = merged.filter { !$0.isDefault }
        return defaultHosts + customHosts
    }

    func add(_ host: Host) {
        guard isValidHost(host) else {
            return
        }

        hosts.append(host)
        ensureDefaultsPresent()
        persistHosts()
    }

    func update(_ host: Host) {
        guard isValidHost(host) else {
            return
        }

        if gatewayHost?.id == host.id {
            gatewayHost = host
            let override = GatewayOverride(address: host.address, pingMethod: host.pingMethod, port: host.port)
            if let data = try? JSONEncoder().encode(override) {
                defaults.set(data, forKey: gatewayOverrideKey)
            }
            return
        }

        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else {
            return
        }

        hosts[index] = host
        ensureDefaultsPresent()
        persistHosts()
    }

    func remove(_ host: Host) {
        guard !host.isDefault else {
            return
        }

        hosts.removeAll { $0.id == host.id }
        ensureDefaultsPresent()
        persistHosts()
    }

    func removeAt(offsets: IndexSet) {
        let nonDefaultIndices = hosts.indices.filter { !hosts[$0].isDefault }
        let mappedOffsets = offsets.compactMap { offset in
            nonDefaultIndices.indices.contains(offset) ? nonDefaultIndices[offset] : nil
        }

        for index in mappedOffsets.sorted(by: >) {
            hosts.remove(at: index)
        }

        ensureDefaultsPresent()
        persistHosts()
    }

    func resetToDefaults() {
        hosts = Host.defaults
        gatewayHost = nil
        persistHosts()
    }

    func isValidHost(_ host: Host) -> Bool {
        !host.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isValidPort(for: host)
    }

    private func isValidPort(for host: Host) -> Bool {
        switch host.pingMethod {
        case .icmp:
            return host.port == 0
        case .tcp, .udp:
            return host.port > 0
        }
    }

    func hostExists(address: String, port: UInt16) -> Bool {
        hosts.contains {
            $0.address.caseInsensitiveCompare(address) == .orderedSame &&
                $0.port == port
        }
    }

    func setGatewayHost(_ info: GatewayInfo) {
        guard info.isAvailable else {
            gatewayHost = nil
            return
        }

        // Apply persisted override if it matches this gateway's IP
        let override = defaults.data(forKey: gatewayOverrideKey)
            .flatMap { try? JSONDecoder().decode(GatewayOverride.self, from: $0) }
        let pingMethod: PingMethod = (override?.address == info.ipAddress) ? override!.pingMethod : .tcp
        let port: UInt16 = (override?.address == info.ipAddress) ? override!.port : 443

        gatewayHost = Host(
            name: info.displayName,
            address: info.ipAddress,
            port: port,
            pingMethod: pingMethod,
            isDefault: true
        )
    }

    func clearGatewayHost() {
        gatewayHost = nil
    }

    func sortedHosts() -> [Host] {
        let defaultHosts = hosts.filter(\.isDefault)
        let customHosts = hosts.filter { !$0.isDefault }

        var ordered = defaultHosts
        if let gatewayHost {
            ordered.append(gatewayHost)
        }

        ordered.append(contentsOf: customHosts)
        return ordered
    }

    var allHosts: [Host] {
        sortedHosts()
    }
}
