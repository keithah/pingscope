import Foundation

actor HostStore {
    private let defaults: UserDefaults
    private let key: String = "pingmonitor.savedHosts"

    private(set) var hosts: [Host]
    private(set) var gatewayHost: Host?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let persistedHosts = Self.loadHosts(from: defaults, key: key)
        if persistedHosts.isEmpty {
            self.hosts = Host.defaults
        } else {
            self.hosts = Self.mergeDefaults(into: persistedHosts)
        }

        self.gatewayHost = nil
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
        do {
            let data = try JSONEncoder().encode(hosts)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }

    private static func mergeDefaults(into loadedHosts: [Host]) -> [Host] {
        var merged = Host.defaults

        for host in loadedHosts {
            let isDuplicateDefault = host.isDefault && merged.contains { $0.name == host.name }
            if !isDuplicateDefault {
                merged.append(host)
            }
        }

        return merged
    }

    func add(_ host: Host) {
        hosts.append(host)
        persistHosts()
    }

    func update(_ host: Host) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else {
            return
        }

        hosts[index] = host
        persistHosts()
    }

    func remove(_ host: Host) {
        guard !host.isDefault else {
            return
        }

        hosts.removeAll { $0.id == host.id }
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

        persistHosts()
    }

    func setGatewayHost(_ info: GatewayInfo) {
        guard info.isAvailable else {
            gatewayHost = nil
            return
        }

        gatewayHost = Host(
            name: info.displayName,
            address: info.ipAddress,
            pingMethod: .tcp,
            isDefault: true
        )
    }

    func clearGatewayHost() {
        gatewayHost = nil
    }

    var allHosts: [Host] {
        let defaultHosts = hosts.filter(\.isDefault)
        let customHosts = hosts.filter { !$0.isDefault }

        var ordered = defaultHosts
        if let gatewayHost {
            ordered.append(gatewayHost)
        }

        ordered.append(contentsOf: customHosts)
        return ordered
    }
}
