import Foundation

public struct SharedHostStoreState: Equatable, Sendable {
    public var hosts: [HostConfig]
    public var primaryHostID: UUID?
    public var selectedHostID: UUID?

    public init(
        hosts: [HostConfig],
        primaryHostID: UUID? = nil,
        selectedHostID: UUID? = nil
    ) {
        self.hosts = hosts
        self.primaryHostID = primaryHostID
        self.selectedHostID = selectedHostID
    }
}

public enum SharedHostStoreReconciliation {
    /// Applies only the host-list changes made by the local app since its last
    /// observed state onto the newest shared state. CloudKit writes can land in
    /// the shared store while an accepted-state callback is queued; treating a
    /// stale app snapshot as a whole-state replacement would erase those writes.
    /// Host records remain whole-value last-writer-wins: a later local edit to
    /// the same host replaces the accepted remote host exactly.
    public static func mergingLocalChanges(
        from baseline: SharedHostStoreState,
        desired local: SharedHostStoreState,
        into latest: SharedHostStoreState
    ) -> SharedHostStoreState {
        let baselineHosts = HostConfig.sanitizedHosts(baseline.hosts)
        let localHosts = HostConfig.sanitizedHosts(local.hosts)
        let latestHosts = HostConfig.sanitizedHosts(latest.hosts)
        let baselineByID = Dictionary(uniqueKeysWithValues: baselineHosts.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: localHosts.map { ($0.id, $0) })
        var mergedByID = Dictionary(uniqueKeysWithValues: latestHosts.map { ($0.id, $0) })
        var mergedOrder = latestHosts.map(\.id)

        let deletedIDs = Set(baselineByID.keys).subtracting(localByID.keys)
        for id in deletedIDs {
            mergedByID[id] = nil
        }
        mergedOrder.removeAll { deletedIDs.contains($0) }

        for host in localHosts where baselineByID[host.id] != host {
            if mergedByID.updateValue(host, forKey: host.id) == nil {
                mergedOrder.append(host.id)
            }
        }

        let baselineOrder = baselineHosts.map(\.id)
        let localOrder = localHosts.map(\.id)
        if baselineOrder != localOrder {
            let localIDs = Set(localOrder)
            let remotelyAddedIDs = mergedOrder.filter { !localIDs.contains($0) && mergedByID[$0] != nil }
            mergedOrder = localOrder.filter { mergedByID[$0] != nil } + remotelyAddedIDs
        }

        let finalIDs = Array(mergedOrder.filter { mergedByID[$0] != nil }.prefix(64))
        let finalIDSet = Set(finalIDs)
        let hosts = finalIDs.compactMap { mergedByID[$0] }
        let primaryCandidate = baseline.primaryHostID != local.primaryHostID
            ? local.primaryHostID
            : latest.primaryHostID
        let selectedCandidate = baseline.selectedHostID != local.selectedHostID
            ? local.selectedHostID
            : latest.selectedHostID
        return SharedHostStoreState(
            hosts: hosts,
            primaryHostID: primaryCandidate.flatMap { finalIDSet.contains($0) ? $0 : nil },
            selectedHostID: selectedCandidate.flatMap { finalIDSet.contains($0) ? $0 : nil }
        )
    }
}

public enum SharedHostStoreCodecError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

public enum SharedHostStoreCodec {
    public static let currentSchemaVersion = 1

    public static func encode(_ state: SharedHostStoreState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return try encoder.encode(Envelope(state: state))
    }

    public static func decode(_ data: Data) throws -> SharedHostStoreState {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return try decoder.decode(Envelope.self, from: data).state
    }
}

public enum SharedHostStoreKeys {
    public static let current = "PingScope.shared.hostStore"
    public static let macHosts = "hostConfigs"
    public static let macPrimaryHostID = "primaryHostID"
    public static let iOSHosts = "PingScope.iOS.hosts"
    public static let iOSSelectedHostID = "PingScope.iOS.selectedHostID"
}

public enum SharedHostStoreLegacyPlatform: Sendable {
    case macOS
    case iOS
}

public enum SharedHostStoreLoadSource: Equatable, Sendable {
    case shared
    case legacy
    case missing
    case unreadable
}

public struct SharedHostStoreLoadResult: Equatable, Sendable {
    public let state: SharedHostStoreState?
    public let source: SharedHostStoreLoadSource

    public init(state: SharedHostStoreState?, source: SharedHostStoreLoadSource) {
        self.state = state
        self.source = source
    }
}

public protocol SharedHostStoring: Sendable {
    func load() -> SharedHostStoreLoadResult
    func save(_ state: SharedHostStoreState) throws
}

/// UserDefaults persistence shared by both applications.
///
/// A current envelope is preferred. Malformed envelopes and schema versions newer
/// than this build are never overwritten during load; the store falls back to the
/// platform's legacy data when available. Saving writes the shared envelope first,
/// then mirrors the legacy representation so a downgraded app retains the latest
/// successfully saved host configuration.
public final class UserDefaultsSharedHostStore: SharedHostStoring, @unchecked Sendable {
    /// Cloud reception and app persistence construct separate store instances
    /// over the same defaults domain. One process-wide coordinator makes the
    /// compare/merge/save step indivisible across every such instance.
    private static let atomicCoordinator = SharedHostStoreAtomicCoordinator()

    private let defaults: UserDefaults
    private let legacyPlatform: SharedHostStoreLegacyPlatform
    private var lastObservedState: SharedHostStoreState?

    public init(defaults: UserDefaults = .standard, legacyPlatform: SharedHostStoreLegacyPlatform) {
        self.defaults = defaults
        self.legacyPlatform = legacyPlatform
    }

    public func load() -> SharedHostStoreLoadResult {
        Self.atomicCoordinator.withLock {
            let result = loadUnlocked()
            lastObservedState = result.state
            return result
        }
    }

    public func save(_ desiredState: SharedHostStoreState) throws {
        try Self.atomicCoordinator.withLock {
            let latest = loadUnlocked()
            let resolvedState = if let baseline = lastObservedState, let latestState = latest.state {
                SharedHostStoreReconciliation.mergingLocalChanges(
                    from: baseline,
                    desired: desiredState,
                    into: latestState
                )
            } else {
                // Without a prior observation there is no trustworthy intent
                // delta to merge. Preserve save()'s whole-state semantics.
                desiredState
            }
            do {
                try saveUnlocked(resolvedState)
            } catch {
                // The shared envelope is written before its legacy mirror. If
                // the mirror cannot encode, retain the envelope as our baseline
                // so a retry does not treat it as an unrelated concurrent edit.
                lastObservedState = resolvedState
                throw error
            }
            lastObservedState = resolvedState
        }
    }

    private func loadUnlocked() -> SharedHostStoreLoadResult {
        var encounteredUnreadableData = false
        if let data = defaults.data(forKey: SharedHostStoreKeys.current) {
            do {
                return SharedHostStoreLoadResult(state: try SharedHostStoreCodec.decode(data), source: .shared)
            } catch {
                encounteredUnreadableData = true
            }
        }

        if let data = defaults.data(forKey: legacyHostsKey) {
            do {
                let hosts = try Self.decodeLegacyHosts(data)
                return SharedHostStoreLoadResult(
                    state: SharedHostStoreState(
                        hosts: hosts,
                        primaryHostID: legacyPlatform == .macOS ? storedUUID(forKey: SharedHostStoreKeys.macPrimaryHostID) : nil,
                        selectedHostID: legacyPlatform == .iOS ? storedUUID(forKey: SharedHostStoreKeys.iOSSelectedHostID) : nil
                    ),
                    source: .legacy
                )
            } catch {
                encounteredUnreadableData = true
            }
        }

        return SharedHostStoreLoadResult(
            state: nil,
            source: encounteredUnreadableData ? .unreadable : .missing
        )
    }

    private func saveUnlocked(_ state: SharedHostStoreState) throws {
        let sharedData = try SharedHostStoreCodec.encode(state)
        defaults.set(sharedData, forKey: SharedHostStoreKeys.current)

        let legacyData = try Self.encodeLegacyHosts(state.hosts)
        defaults.set(legacyData, forKey: legacyHostsKey)
        switch legacyPlatform {
        case .macOS:
            defaults.set(state.primaryHostID?.uuidString, forKey: SharedHostStoreKeys.macPrimaryHostID)
        case .iOS:
            defaults.set(state.selectedHostID?.uuidString, forKey: SharedHostStoreKeys.iOSSelectedHostID)
        }
    }

    private var legacyHostsKey: String {
        switch legacyPlatform {
        case .macOS: SharedHostStoreKeys.macHosts
        case .iOS: SharedHostStoreKeys.iOSHosts
        }
    }

    private func storedUUID(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private static func encodeLegacyHosts(_ hosts: [HostConfig]) throws -> Data {
        try JSONEncoder().encode(hosts)
    }

    private static func decodeLegacyHosts(_ data: Data) throws -> [HostConfig] {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return try decoder.decode(LossyHostConfigArray.self, from: data).values
    }
}

private final class SharedHostStoreAtomicCoordinator: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private struct Envelope: Codable {
    let schemaVersion: Int
    let hosts: [HostConfig]
    let primaryHostID: UUID?
    let selectedHostID: UUID?

    init(state: SharedHostStoreState) {
        schemaVersion = SharedHostStoreCodec.currentSchemaVersion
        hosts = state.hosts
        primaryHostID = state.primaryHostID
        selectedHostID = state.selectedHostID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == SharedHostStoreCodec.currentSchemaVersion else {
            throw SharedHostStoreCodecError.unsupportedSchemaVersion(schemaVersion)
        }
        hosts = try container.decode([LossyHostConfig].self, forKey: .hosts).compactMap(\.value)
        primaryHostID = try container.decodeIfPresent(UUID.self, forKey: .primaryHostID)
        selectedHostID = try container.decodeIfPresent(UUID.self, forKey: .selectedHostID)
    }

    var state: SharedHostStoreState {
        SharedHostStoreState(
            hosts: hosts,
            primaryHostID: primaryHostID,
            selectedHostID: selectedHostID
        )
    }
}

private struct LossyHostConfig: Decodable {
    let value: HostConfig?

    init(from decoder: Decoder) throws {
        value = try? HostConfig(from: decoder)
    }
}

private struct LossyHostConfigArray: Decodable {
    let values: [HostConfig]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [HostConfig] = []
        while !container.isAtEnd {
            decoded.append(contentsOf: try container.decode(LossyHostConfig.self).value.map { [$0] } ?? [])
        }
        values = decoded
    }
}
