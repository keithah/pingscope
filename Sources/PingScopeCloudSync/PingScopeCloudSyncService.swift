@preconcurrency import CloudKit
import Foundation
import PingScopeCore

public enum PingScopeCloudSyncPreference {
    public static let enabledKey = "PingScope.CloudSync.Enabled"

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}

private actor CloudSyncHostVersionRegistry {
    private static let defaultsKey = "PingScope.CloudSync.HostModifiedAt"
    private static let configDefaultsKey = "PingScope.CloudSync.HostConfig"
    private static let pendingDeletionDefaultsKey = "PingScope.CloudSync.PendingHostDeletions"
    private let defaults: UserDefaults
    private var modifiedAtByID: [UUID: Date]
    private var configByID: [UUID: HostConfig]
    private var pendingDeletionIDs: Set<UUID>

    init(suiteName: String? = nil) {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        let persisted = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        self.modifiedAtByID = Dictionary(uniqueKeysWithValues: persisted.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
        let persistedConfigs: [String: HostConfig]
        if let data = defaults.data(forKey: Self.configDefaultsKey) {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "+Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            persistedConfigs = (try? decoder.decode([String: HostConfig].self, from: data)) ?? [:]
        } else {
            persistedConfigs = [:]
        }
        self.configByID = Dictionary(uniqueKeysWithValues: persistedConfigs.compactMap { key, config in
            UUID(uuidString: key).map { ($0, config) }
        })
        self.pendingDeletionIDs = Set(
            (defaults.stringArray(forKey: Self.pendingDeletionDefaultsKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    func modifiedAt(for id: UUID) -> Date? { modifiedAtByID[id] }

    func changedVersions(
        for hosts: [HostConfig],
        modifiedAt: Date
    ) -> [CloudSyncHostVersion] {
        hosts.compactMap { host in
            guard !pendingDeletionIDs.contains(host.id), configByID[host.id] != host else { return nil }
            return CloudSyncHostVersion(config: host, modifiedAt: modifiedAt)
        }
    }

    func pendingDeletions() -> Set<UUID> { pendingDeletionIDs }
    func isPendingDeletion(_ id: UUID) -> Bool { pendingDeletionIDs.contains(id) }

    func markPendingDeletion(_ id: UUID) {
        pendingDeletionIDs.insert(id)
        persist()
    }

    func set(_ version: CloudSyncHostVersion) {
        modifiedAtByID[version.config.id] = version.modifiedAt
        configByID[version.config.id] = version.config
        persist()
    }

    func set(_ versions: [CloudSyncHostVersion]) {
        guard !versions.isEmpty else { return }
        for version in versions {
            modifiedAtByID[version.config.id] = version.modifiedAt
            configByID[version.config.id] = version.config
        }
        persist()
    }

    func confirmDeletion(_ id: UUID) {
        pendingDeletionIDs.remove(id)
        modifiedAtByID[id] = nil
        configByID[id] = nil
        persist()
    }

    private func persist() {
        defaults.set(
            Dictionary(uniqueKeysWithValues: modifiedAtByID.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) }),
            forKey: Self.defaultsKey
        )
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let configs = Dictionary(uniqueKeysWithValues: configByID.map { ($0.key.uuidString, $0.value) })
        if let data = try? encoder.encode(configs) {
            defaults.set(data, forKey: Self.configDefaultsKey)
        }
        defaults.set(
            pendingDeletionIDs.map(\.uuidString).sorted(),
            forKey: Self.pendingDeletionDefaultsKey
        )
    }
}

private actor CloudSyncRemoteReceiver {
    private let historyStore: any PingHistoryStore
    private let hostStore: any SharedHostStoring
    private let versions: CloudSyncHostVersionRegistry

    init(
        historyStore: any PingHistoryStore,
        hostStore: any SharedHostStoring,
        versions: CloudSyncHostVersionRegistry
    ) {
        self.historyStore = historyStore
        self.hostStore = hostStore
        self.versions = versions
    }

    func apply(records: [CKRecord], deletions: [CloudSyncRemoteDeletion]) async {
        let sampleRecords = records.filter {
            $0.recordType == PingScopeCloudKitModel.RecordType.pingSample
        }
        try? await CloudSyncRemoteChangeApplier.apply(sampleRecords: sampleRecords, to: historyStore)

        var hostState = hostStore.load().state ?? SharedHostStoreState(hosts: [])
        var didChangeHosts = false
        for record in records where record.recordType == PingScopeCloudKitModel.RecordType.monitoredHost {
            guard let remote = MonitoredHostRecordMapper.monitoredHost(from: record) else { continue }
            guard !(await versions.isPendingDeletion(remote.config.id)) else { continue }
            let remoteVersion = CloudSyncHostVersion(config: remote.config, modifiedAt: remote.modifiedAt)
            if let localConfig = hostState.hosts.first(where: { $0.id == remote.config.id }) {
                let localVersion = CloudSyncHostVersion(
                    config: localConfig,
                    modifiedAt: await versions.modifiedAt(for: localConfig.id) ?? .distantPast
                )
                guard CloudSyncConflictResolver.resolve(local: localVersion, remote: remoteVersion) == remoteVersion else {
                    continue
                }
            }
            if let index = hostState.hosts.firstIndex(where: { $0.id == remote.config.id }) {
                hostState.hosts[index] = remote.config
            } else {
                hostState.hosts.append(remote.config)
            }
            await versions.set(remoteVersion)
            didChangeHosts = true
        }

        let sampleDeletionIDs = deletions
            .filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
            .map(\.recordID)
        try? await CloudSyncRemoteChangeApplier.deleteSampleRecordIDs(sampleDeletionIDs, from: historyStore)

        for deletion in deletions where deletion.recordType == PingScopeCloudKitModel.RecordType.monitoredHost {
            guard let id = UUID(uuidString: deletion.recordID.recordName) else { continue }
            let previousCount = hostState.hosts.count
            hostState.hosts.removeAll { $0.id == id }
            if hostState.primaryHostID == id { hostState.primaryHostID = nil }
            if hostState.selectedHostID == id { hostState.selectedHostID = nil }
            await versions.confirmDeletion(id)
            didChangeHosts = didChangeHosts || previousCount != hostState.hosts.count
        }
        if didChangeHosts {
            try? hostStore.save(hostState)
        }
    }
}

public actor PingScopeCloudSyncService {
    private let historyStore: any PingHistoryStore
    private let hostStore: any SharedHostStoring
    private let receiver: CloudSyncRemoteReceiver
    private let coordinator: PingScopeCloudSyncCoordinator
    private let versions: CloudSyncHostVersionRegistry
    private var isDrainingBacklog = false

    public init(
        historyStore: any PingHistoryStore,
        hostStore: any SharedHostStoring
    ) {
        let versions = CloudSyncHostVersionRegistry()
        let receiver = CloudSyncRemoteReceiver(
            historyStore: historyStore,
            hostStore: hostStore,
            versions: versions
        )
        let boundary = CKSyncEngineBoundary { records, deletions in
            await receiver.apply(records: records, deletions: deletions)
        }
        self.historyStore = historyStore
        self.hostStore = hostStore
        self.receiver = receiver
        self.versions = versions
        self.coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
    }

    init(
        historyStore: any PingHistoryStore,
        hostStore: any SharedHostStoring,
        boundary: any CloudSyncEngineBoundary,
        recordBuilder: any CloudSyncRecordBuilding,
        registrySuiteName: String
    ) {
        let versions = CloudSyncHostVersionRegistry(suiteName: registrySuiteName)
        let receiver = CloudSyncRemoteReceiver(
            historyStore: historyStore,
            hostStore: hostStore,
            versions: versions
        )
        self.historyStore = historyStore
        self.hostStore = hostStore
        self.receiver = receiver
        self.versions = versions
        self.coordinator = PingScopeCloudSyncCoordinator(
            boundary: boundary,
            recordBuilder: recordBuilder
        )
    }

    func applyRemoteChanges(records: [CKRecord], deletions: [CloudSyncRemoteDeletion] = []) async {
        await receiver.apply(records: records, deletions: deletions)
    }

    public func setEnabled(_ enabled: Bool, hosts: [HostConfig]) async {
        await coordinator.setEnabled(enabled)
        guard enabled else { return }
        await drainPendingHostDeletions()
        // start() fetches and applies remote changes first. Read the reconciled
        // shared store afterward so a remote edit/deletion is not overwritten by
        // the pre-fetch app snapshot captured when enable began.
        let pendingDeletionIDs = await versions.pendingDeletions()
        let reconciledHosts = (hostStore.load().state?.hosts ?? hosts).filter {
            !pendingDeletionIDs.contains($0.id)
        }
        await uploadInitialHosts(reconciledHosts)
        await drainBacklog()
    }

    @discardableResult
    public func uploadSamples(_ samples: [PingResult]) async -> Bool {
        let uploaded = await uploadSampleBatch(samples)
        if uploaded {
            await drainPendingHostDeletions()
            await drainBacklog()
        }
        return uploaded
    }

    private func uploadSampleBatch(_ samples: [PingResult]) async -> Bool {
        do {
            let uploaded = try await coordinator.upload(samples: samples, hosts: [])
            if uploaded { try await historyStore.markSamplesSynced(ids: samples.map(\.id)) }
            return uploaded
        } catch {
            return false
        }
    }

    public func uploadHosts(_ hosts: [HostConfig], modifiedAt: Date = Date()) async {
        let changedVersions = await versions.changedVersions(for: hosts, modifiedAt: modifiedAt)
        guard !changedVersions.isEmpty else { return }
        guard (try? await coordinator.upload(samples: [], hosts: changedVersions)) == true else { return }
        await versions.set(changedVersions)
    }

    private func uploadInitialHosts(_ hosts: [HostConfig]) async {
        let now = Date()
        var initialVersions: [CloudSyncHostVersion] = []
        initialVersions.reserveCapacity(hosts.count)
        for host in hosts {
            guard !(await versions.isPendingDeletion(host.id)) else { continue }
            let modifiedAt = await versions.modifiedAt(for: host.id) ?? now
            initialVersions.append(CloudSyncHostVersion(config: host, modifiedAt: modifiedAt))
        }
        guard (try? await coordinator.upload(samples: [], hosts: initialVersions)) == true else { return }
        await versions.set(initialVersions)
    }

    private func drainBacklog() async {
        guard !isDrainingBacklog else { return }
        isDrainingBacklog = true
        defer { isDrainingBacklog = false }
        while let samples = try? await historyStore.unsyncedSamples(limit: 300), !samples.isEmpty {
            guard await uploadSampleBatch(samples) else { return }
        }
    }

    private func drainPendingHostDeletions() async {
        let pendingIDs = await versions.pendingDeletions().sorted { $0.uuidString < $1.uuidString }
        for id in pendingIDs where await uploadHostDeletion(id) {
            await versions.confirmDeletion(id)
        }
    }

    private func uploadHostDeletion(_ id: UUID) async -> Bool {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: PingScopeCloudKitModel.zoneID)
        do {
            return try await coordinator.upload(samples: [], hosts: [], deletions: [recordID])
        } catch let error as CKError where error.code == .unknownItem {
            return true
        } catch {
            return false
        }
    }

    public func deleteHost(id: UUID) async {
        await versions.markPendingDeletion(id)
        guard await uploadHostDeletion(id) else { return }
        await versions.confirmDeletion(id)
    }

    public func status() async -> PingScopeCloudSyncStatus {
        await coordinator.status
    }
}

public struct CloudSyncingHistoryStore: PingHistoryStore {
    private let destination: any PingHistoryStore
    private let service: PingScopeCloudSyncService

    public init(destination: any PingHistoryStore, service: PingScopeCloudSyncService) {
        self.destination = destination
        self.service = service
    }

    public func append(_ result: PingResult) async {
        await destination.append(result)
        await service.uploadSamples([result])
    }

    public func append(_ results: [PingResult]) async {
        await destination.append(results)
        await service.uploadSamples(results)
    }

    public func appendAndWait(_ results: [PingResult]) async throws {
        try await destination.appendAndWait(results)
        await service.uploadSamples(results)
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

    public func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        try await destination.exportSamples(host: host, since: since, format: format, to: url)
    }

    public func prune(olderThan cutoff: Date) async { await destination.prune(olderThan: cutoff) }
    public func deleteAll() async { await destination.deleteAll() }
}
