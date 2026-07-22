import Foundation

public enum NetworkInterfaceNormalizer {
    public static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wifi", "wi-fi", "wlan": "wifi"
        case "cell", "cellular": "cellular"
        case "wired", "wiredethernet", "ethernet": "wired"
        case "other": "other"
        default: "other"
        }
    }

    public static func displayName(for interface: String?) -> String {
        switch normalize(interface) {
        case "wifi": "Wi-Fi"
        case "cellular": "Cellular"
        case "wired": "Wired"
        default: "Other"
        }
    }
}

public enum NetworkVPNHeuristic {
    private static let tunnelPrefixes = ["utun", "tun", "tap", "ppp", "ipsec"]

    public static func isVPN(activeInterfaceNames: [String]) -> Bool {
        activeInterfaceNames.contains { name in
            let normalized = name.lowercased()
            return tunnelPrefixes.contains { normalized.hasPrefix($0) }
        }
    }
}

/// Resolves a platform-supplied interface and injectable label providers into
/// the stable network fields persisted with history. Apple framework access
/// remains in the app targets; tests can supply deterministic providers.
public struct NetworkCaptureResolver: Sendable {
    private let activeInterfaceNames: @Sendable () -> [String]
    private let wifiName: @Sendable () -> String?
    private let cellularRadio: @Sendable () -> String?

    public init(
        activeInterfaceNames: @escaping @Sendable () -> [String],
        wifiName: @escaping @Sendable () -> String?,
        cellularRadio: @escaping @Sendable () -> String?
    ) {
        self.activeInterfaceNames = activeInterfaceNames
        self.wifiName = wifiName
        self.cellularRadio = cellularRadio
    }

    public func snapshot(
        interface: String?,
        isWiFiNameAuthorized: Bool = false
    ) -> NetworkCaptureSnapshot {
        let normalizedInterface = NetworkInterfaceNormalizer.normalize(interface)
        let name: String? = switch normalizedInterface {
        case "wifi" where isWiFiNameAuthorized:
            nonempty(wifiName())
        case "cellular":
            nonempty(cellularRadio()).map { "Cellular · \($0)" }
        default:
            nil
        }
        return NetworkCaptureSnapshot(
            interface: normalizedInterface,
            name: name,
            isVPN: NetworkVPNHeuristic.isVPN(activeInterfaceNames: activeInterfaceNames())
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct NetworkCaptureSnapshot: Equatable, Sendable {
    public var interface: String?
    public var name: String?
    public var isVPN: Bool

    public init(interface: String? = nil, name: String? = nil, isVPN: Bool = false) {
        let normalizedInterface = NetworkInterfaceNormalizer.normalize(interface)
        self.interface = normalizedInterface
        self.name = name ?? normalizedInterface.map(NetworkInterfaceNormalizer.displayName(for:))
        self.isVPN = isVPN
    }

    public func stamping(_ result: PingResult) -> PingResult {
        var stamped = result
        stamped.networkInterface = interface
        stamped.networkName = name
        stamped.isVPN = isVPN
        if let location = result.location {
            stamped.location = SampleLocation(
                latitude: location.latitude,
                longitude: location.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                networkName: name,
                networkInterface: interface
            )
        }
        return stamped
    }
}

public final class NetworkCaptureSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: NetworkCaptureSnapshot

    public init(snapshot: NetworkCaptureSnapshot = .init(interface: "other", name: "Other")) {
        value = snapshot
    }

    public func snapshot() -> NetworkCaptureSnapshot {
        lock.withLock { value }
    }

    public func update(_ snapshot: NetworkCaptureSnapshot) {
        lock.withLock { value = snapshot }
    }

    public func updateName(_ name: String, ifInterfaceMatches interface: String) {
        let normalized = NetworkInterfaceNormalizer.normalize(interface)
        lock.withLock {
            guard value.interface == normalized else { return }
            value.name = name
        }
    }
}

/// A `PingHistoryStore` decorator that stamps the current network label onto
/// every persisted sample (via the shared `NetworkCaptureSnapshotStore`) while
/// leaving the caller's original `PingResult` untouched. Reads forward to the
/// wrapped destination unchanged. Platform-neutral so both macOS and iOS wrap
/// their `SQLiteHistoryStore` with it.
public struct NetworkCapturedHistoryStore: PingHistoryStore {
    private let destination: any PingHistoryStore
    private let networkCaptureStore: NetworkCaptureSnapshotStore

    public init(destination: any PingHistoryStore, networkCaptureStore: NetworkCaptureSnapshotStore) {
        self.destination = destination
        self.networkCaptureStore = networkCaptureStore
    }

    private func stamped(_ result: PingResult) -> PingResult {
        networkCaptureStore.snapshot().stamping(result)
    }

    public func append(_ result: PingResult) async {
        await destination.append(stamped(result))
    }

    public func append(_ results: [PingResult]) async {
        await destination.append(results.map(stamped))
    }

    public func appendAndWait(_ results: [PingResult]) async throws {
        try await destination.appendAndWait(results.map(stamped))
    }

    public func upsertRemoteSamples(_ results: [PingResult]) async throws {
        try await destination.upsertRemoteSamples(results)
    }

    public func deleteSamples(ids: [UUID]) async throws {
        try await destination.deleteSamples(ids: ids)
    }

    public func unsyncedSamples(limit: Int) async throws -> [PingResult] {
        try await destination.unsyncedSamples(limit: limit)
    }

    public func markSamplesSynced(ids: [UUID]) async throws {
        try await destination.markSamplesSynced(ids: ids)
    }

    public func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        await destination.samples(hostID: hostID, since: since, limit: limit)
    }

    public func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        await destination.latestSamples(hostID: hostID, since: since, limit: limit)
    }

    public func weeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) async -> [HistoryWeeklyDigestSample] {
        await destination.weeklyDigestSamples(hostIDs: hostIDs, since: since, through: through)
    }

    public func historyRevision() async -> UInt64 {
        await destination.historyRevision()
    }

    public func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        try await destination.exportSamples(host: host, since: since, format: format, to: url)
    }

    public func prune(olderThan cutoff: Date) async {
        await destination.prune(olderThan: cutoff)
    }

    public func deleteAll() async {
        await destination.deleteAll()
    }
}
