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

public enum PingScopeIOSHostOrdering {
    public static func reordered(hosts: [HostConfig], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [HostConfig] {
        let sortedOffsets = offsets.sorted()
        guard !sortedOffsets.isEmpty else { return hosts }
        var result = hosts
        let movingHosts = sortedOffsets.compactMap { index in
            hosts.indices.contains(index) ? hosts[index] : nil
        }
        for index in sortedOffsets.reversed() where result.indices.contains(index) {
            result.remove(at: index)
        }
        let removedBeforeDestination = sortedOffsets.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), result.count)
        result.insert(contentsOf: movingHosts, at: insertionIndex)
        return result
    }
}

public final class PingScopeIOSHostStore: @unchecked Sendable {
    public static let defaultHosts: [HostConfig] = BuildFlavor.appStore.normalizedHosts(HostConfig.defaultHosts())

    private let defaults: UserDefaults
    private let defaultHosts: [HostConfig]
    private let hostsKey = "PingScope.iOS.hosts"
    private let selectedHostIDKey = "PingScope.iOS.selectedHostID"

    public init(defaults: UserDefaults = .standard, defaultHosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts) {
        self.defaults = defaults
        let sanitizedDefaults = HostConfig.sanitizedHosts(defaultHosts)
        self.defaultHosts = sanitizedDefaults.isEmpty ? BuildFlavor.appStore.normalizedHosts(HostConfig.defaultHosts()) : sanitizedDefaults
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
        let sanitizedHosts = HostConfig.sanitizedHosts(hosts.isEmpty ? defaultHosts : hosts)
        let normalizedHosts = sanitizedHosts.isEmpty ? defaultHosts : sanitizedHosts
        let selectedID = normalizedHosts.contains { $0.id == selectedHostID } ? selectedHostID : normalizedHosts[0].id
        do {
            let data = try JSONEncoder().encode(normalizedHosts)
            defaults.set(data, forKey: hostsKey)
            defaults.set(selectedID.uuidString, forKey: selectedHostIDKey)
        } catch {
            NSLog("PingScope iOS host encode failed: \(error.localizedDescription)")
        }
    }

    private func loadHosts() -> [HostConfig] {
        let stored = defaults.data(forKey: hostsKey)
        if let stored {
            do {
                let hosts = try JSONDecoder().decode([HostConfig].self, from: stored)
                if !hosts.isEmpty {
                    return hosts
                }
                NSLog("PingScope iOS host decode produced no hosts")
            } catch {
                NSLog("PingScope iOS host decode failed: \(error.localizedDescription)")
            }
        }
        // First launch: persist the generated defaults immediately so their IDs
        // are stable across launches. History rows are keyed by host ID, so
        // handing out unsaved defaults would mint fresh IDs on every relaunch
        // and orphan all previously recorded samples. Only when nothing is
        // stored, though: a blob that merely fails to decode (written by a
        // newer app version, or transiently corrupt) must be left intact, or
        // the user's saved hosts would be destroyed on the first failed read.
        if stored == nil {
            do {
                let data = try JSONEncoder().encode(defaultHosts)
                defaults.set(data, forKey: hostsKey)
            } catch {
                NSLog("PingScope iOS default host encode failed: \(error.localizedDescription)")
            }
        }
        return defaultHosts
    }
}
