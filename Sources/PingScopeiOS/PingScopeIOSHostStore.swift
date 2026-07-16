import Foundation
import PingScopeCore

public enum PingScopeIOSHostScope: String, Codable, Sendable {
    case focused
    case allHosts
}

public struct PingScopeIOSHostState: Equatable, Sendable {
    public var hosts: [HostConfig]
    public var selectedHost: HostConfig
    public var hostScope: PingScopeIOSHostScope

    public init(hosts: [HostConfig], selectedHost: HostConfig, hostScope: PingScopeIOSHostScope = .focused) {
        self.hosts = hosts
        self.selectedHost = selectedHost
        self.hostScope = hostScope
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
    private let sharedStore: UserDefaultsSharedHostStore
    private let hostScopeKey = "PingScope.iOS.hostScope"

    public init(defaults: UserDefaults = .standard, defaultHosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts) {
        self.defaults = defaults
        sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .iOS)
        let sanitizedDefaults = HostConfig.sanitizedHosts(defaultHosts)
        self.defaultHosts = sanitizedDefaults.isEmpty ? BuildFlavor.appStore.normalizedHosts(HostConfig.defaultHosts()) : sanitizedDefaults
    }

    public func load() -> PingScopeIOSHostState {
        let loaded = loadHosts()
        let hosts = loaded.hosts
        let selectedID = loaded.selectedHostID
        let selectedHost = selectedID.flatMap { id in
            hosts.first { $0.id == id }
        } ?? hosts[0]
        return PingScopeIOSHostState(hosts: hosts, selectedHost: selectedHost, hostScope: loadHostScope())
    }

    public func save(hosts: [HostConfig], selectedHostID: UUID) {
        save(hosts: hosts, selectedHostID: selectedHostID, hostScope: loadHostScope())
    }

    public func save(hosts: [HostConfig], selectedHostID: UUID, hostScope: PingScopeIOSHostScope) {
        let sanitizedHosts = HostConfig.sanitizedHosts(hosts.isEmpty ? defaultHosts : hosts)
        let normalizedHosts = sanitizedHosts.isEmpty ? defaultHosts : sanitizedHosts
        let selectedID = normalizedHosts.contains { $0.id == selectedHostID } ? selectedHostID : normalizedHosts[0].id
        do {
            let existingPrimaryHostID = sharedStore.load().state?.primaryHostID
            try sharedStore.save(
                SharedHostStoreState(
                    hosts: normalizedHosts,
                    primaryHostID: existingPrimaryHostID,
                    selectedHostID: selectedID
                )
            )
            defaults.set(hostScope.rawValue, forKey: hostScopeKey)
        } catch {
            NSLog("PingScope iOS host encode failed: \(error.localizedDescription)")
        }
    }

    private func loadHostScope() -> PingScopeIOSHostScope {
        defaults.string(forKey: hostScopeKey).flatMap(PingScopeIOSHostScope.init(rawValue:)) ?? .focused
    }

    private func loadHosts() -> (hosts: [HostConfig], selectedHostID: UUID?) {
        let loaded = sharedStore.load()
        if let state = loaded.state {
            // Mirror save(): duplicate IDs and invalid hosts must not flow into
            // UI/coordinator keying. This does not rewrite stored bytes.
            let hosts = HostConfig.sanitizedHosts(state.hosts)
            if !hosts.isEmpty {
                return (hosts, state.selectedHostID)
            }
            NSLog("PingScope iOS host decode produced no hosts")
        } else if loaded.source == .unreadable {
            NSLog("PingScope iOS host decode failed")
        }
        // First launch: persist the generated defaults immediately so their IDs
        // are stable across launches. History rows are keyed by host ID, so
        // handing out unsaved defaults would mint fresh IDs on every relaunch
        // and orphan all previously recorded samples. Only when nothing is
        // stored, though: a blob that merely fails to decode (written by a
        // newer app version, or transiently corrupt) must be left intact, or
        // the user's saved hosts would be destroyed on the first failed read.
        if loaded.source == .missing {
            do {
                try sharedStore.save(
                    SharedHostStoreState(hosts: defaultHosts, selectedHostID: defaultHosts.first?.id)
                )
            } catch {
                NSLog("PingScope iOS default host encode failed: \(error.localizedDescription)")
            }
        }
        return (defaultHosts, nil)
    }
}
