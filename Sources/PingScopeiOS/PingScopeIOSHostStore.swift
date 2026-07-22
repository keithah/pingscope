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
    private var lastObservedSharedState: SharedHostStoreState?

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
        lastObservedSharedState = SharedHostStoreState(
            hosts: hosts,
            primaryHostID: loaded.primaryHostID,
            selectedHostID: selectedHost.id
        )
        return PingScopeIOSHostState(hosts: hosts, selectedHost: selectedHost, hostScope: loadHostScope())
    }

    @discardableResult
    public func save(hosts: [HostConfig], selectedHostID: UUID) -> PingScopeIOSHostState {
        save(hosts: hosts, selectedHostID: selectedHostID, hostScope: loadHostScope())
    }

    @discardableResult
    public func save(
        hosts: [HostConfig],
        selectedHostID: UUID,
        hostScope: PingScopeIOSHostScope
    ) -> PingScopeIOSHostState {
        let sanitizedHosts = HostConfig.sanitizedHosts(hosts.isEmpty ? defaultHosts : hosts)
        let normalizedHosts = sanitizedHosts.isEmpty ? defaultHosts : sanitizedHosts
        let selectedID = normalizedHosts.contains { $0.id == selectedHostID } ? selectedHostID : normalizedHosts[0].id
        let latest = sharedStore.load().state.map(Self.sanitizedSharedState)
        let desired = SharedHostStoreState(
            hosts: normalizedHosts,
            primaryHostID: latest?.primaryHostID ?? lastObservedSharedState?.primaryHostID,
            selectedHostID: selectedID
        )
        let baseline = lastObservedSharedState ?? latest ?? desired
        let resolved = latest.map {
            SharedHostStoreReconciliation.mergingLocalChanges(
                from: baseline,
                desired: desired,
                into: $0
            )
        } ?? desired
        do {
            try sharedStore.save(resolved)
            defaults.set(hostScope.rawValue, forKey: hostScopeKey)
            lastObservedSharedState = resolved
        } catch {
            NSLog("PingScope iOS host encode failed: \(error.localizedDescription)")
            return load()
        }
        guard !resolved.hosts.isEmpty else { return load() }
        let selectedHost = resolved.selectedHostID.flatMap { id in
            resolved.hosts.first { $0.id == id }
        } ?? resolved.hosts[0]
        return PingScopeIOSHostState(hosts: resolved.hosts, selectedHost: selectedHost, hostScope: hostScope)
    }

    /// Resolves a queued CloudKit notification at the point it will mutate the
    /// app model. A concurrent local save may have advanced the shared state
    /// after the callback captured its argument.
    public func resolveAcceptedHostState(_ captured: SharedHostStoreState) -> SharedHostStoreState {
        sharedStore.load().state.map(Self.sanitizedSharedState)
            ?? Self.sanitizedSharedState(captured)
    }

    /// Advances the local merge baseline only after the resolved state has
    /// survived app/session reconciliation. Merely resolving must not make a
    /// concurrent local save treat uncommitted remote fields as local edits.
    public func commitAcceptedHostState(_ state: SharedHostStoreState) {
        lastObservedSharedState = Self.sanitizedSharedState(state)
    }

    private func loadHostScope() -> PingScopeIOSHostScope {
        defaults.string(forKey: hostScopeKey).flatMap(PingScopeIOSHostScope.init(rawValue:)) ?? .focused
    }

    private func loadHosts() -> (hosts: [HostConfig], primaryHostID: UUID?, selectedHostID: UUID?) {
        let loaded = sharedStore.load()
        if let state = loaded.state {
            // Mirror save(): duplicate IDs and invalid hosts must not flow into
            // UI/coordinator keying. This does not rewrite stored bytes.
            let hosts = HostConfig.sanitizedHosts(state.hosts)
            if !hosts.isEmpty {
                return (hosts, state.primaryHostID, state.selectedHostID)
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
        return (defaultHosts, nil, nil)
    }

    private static func sanitizedSharedState(_ state: SharedHostStoreState) -> SharedHostStoreState {
        let hosts = HostConfig.sanitizedHosts(state.hosts)
        let ids = Set(hosts.map(\.id))
        return SharedHostStoreState(
            hosts: hosts,
            primaryHostID: state.primaryHostID.flatMap { ids.contains($0) ? $0 : nil },
            selectedHostID: state.selectedHostID.flatMap { ids.contains($0) ? $0 : nil }
        )
    }
}
