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
    private let onPersist: @Sendable () -> Void
    private var modifiedAtByID: [UUID: Date]
    private var configByID: [UUID: HostConfig]
    private var pendingDeletionIDs: Set<UUID>

    init(
        suiteName: String? = nil,
        onPersist: @escaping @Sendable () -> Void = {}
    ) {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        self.onPersist = onPersist
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

    func applyBatch(
        _ versions: [CloudSyncHostVersion],
        confirmingDeletions deletionIDs: Set<UUID>
    ) {
        guard !versions.isEmpty || !deletionIDs.isEmpty else { return }
        for version in versions {
            modifiedAtByID[version.config.id] = version.modifiedAt
            configByID[version.config.id] = version.config
        }
        for id in deletionIDs {
            pendingDeletionIDs.remove(id)
            modifiedAtByID[id] = nil
            configByID[id] = nil
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
        onPersist()
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
        let originalHostState = hostState
        let sanitizedLocalHosts = HostConfig.sanitizedHosts(hostState.hosts, limit: 64)
        var hostOrder = sanitizedLocalHosts.map(\.id)
        var hostsByID = Dictionary(uniqueKeysWithValues: sanitizedLocalHosts.map { ($0.id, $0) })
        var acceptedVersionsByID: [UUID: CloudSyncHostVersion] = [:]
        for record in records where record.recordType == PingScopeCloudKitModel.RecordType.monitoredHost {
            guard let remote = MonitoredHostRecordMapper.monitoredHost(from: record) else { continue }
            guard !(await versions.isPendingDeletion(remote.config.id)) else { continue }
            let remoteVersion = CloudSyncHostVersion(config: remote.config, modifiedAt: remote.modifiedAt)
            if let localConfig = hostsByID[remote.config.id] {
                let localModifiedAt: Date
                if let acceptedVersion = acceptedVersionsByID[localConfig.id] {
                    localModifiedAt = acceptedVersion.modifiedAt
                } else {
                    localModifiedAt = await versions.modifiedAt(for: localConfig.id) ?? .distantPast
                }
                let localVersion = CloudSyncHostVersion(
                    config: localConfig,
                    modifiedAt: localModifiedAt
                )
                guard CloudSyncConflictResolver.resolve(local: localVersion, remote: remoteVersion) == remoteVersion else {
                    continue
                }
            }
            if hostsByID.updateValue(remote.config, forKey: remote.config.id) == nil {
                hostOrder.append(remote.config.id)
            }
            acceptedVersionsByID[remote.config.id] = remoteVersion
        }

        let sampleDeletionIDs = deletions
            .filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
            .map(\.recordID)
        try? await CloudSyncRemoteChangeApplier.deleteSampleRecordIDs(sampleDeletionIDs, from: historyStore)

        let confirmedDeletionIDs = Set(deletions.compactMap { deletion -> UUID? in
            guard deletion.recordType == PingScopeCloudKitModel.RecordType.monitoredHost else { return nil }
            return UUID(uuidString: deletion.recordID.recordName)
        })
        for id in confirmedDeletionIDs {
            hostsByID[id] = nil
            acceptedVersionsByID[id] = nil
        }

        hostOrder.removeAll { hostsByID[$0] == nil }
        let finalHostIDs = Array(hostOrder.prefix(64))
        let finalHostIDSet = Set(finalHostIDs)
        hostState.hosts = finalHostIDs.compactMap { hostsByID[$0] }
        if let primaryHostID = hostState.primaryHostID, !finalHostIDSet.contains(primaryHostID) {
            hostState.primaryHostID = nil
        }
        if let selectedHostID = hostState.selectedHostID, !finalHostIDSet.contains(selectedHostID) {
            hostState.selectedHostID = nil
        }
        let acceptedVersions = finalHostIDs.compactMap { acceptedVersionsByID[$0] }

        if hostState != originalHostState {
            do {
                try hostStore.save(hostState)
            } catch {
                return
            }
        }
        await versions.applyBatch(acceptedVersions, confirmingDeletions: confirmedDeletionIDs)
    }
}

public actor PingScopeCloudSyncService {
    private static let sampleUploadBatchLimit = 300
    private static let acknowledgementRetryLimit = 3
    private static let sampleDrainAccumulationDelay = Duration.milliseconds(10)
    private static let defaultSampleRetryDelay = Duration.seconds(1)
    private static let maximumSampleRetryDelay = 60_000.0

    private let historyStore: any PingHistoryStore
    private let hostStore: any SharedHostStoring
    private let receiver: CloudSyncRemoteReceiver
    private let coordinator: PingScopeCloudSyncCoordinator
    private let versions: CloudSyncHostVersionRegistry
    private let sleep: @Sendable (Duration) async throws -> Void
    private let beforeDisableCoordinatorTeardown: @Sendable () async -> Void
    private let afterDisableAuthorizationTeardown: @Sendable () async -> Void
    private var requestedSyncEnabled = false
    private var requestedHosts: [HostConfig] = []
    private var isSyncEnabled = false
    private var lifecycleGeneration: UInt = 0
    private var drainGeneration: UInt = 0
    private var drainRequested = false
    private var drainTask: Task<Void, Never>?
    private var accumulationTask: Task<Void, Never>?
    private var accumulationGeneration: UInt = 0
    private var retryTask: Task<Void, Never>?
    private var retryGeneration: UInt = 0
    private var consecutiveRetryCount = 0
    private var sampleIDsAwaitingLocalAcknowledgement: [UUID] = []
    private var lastDrainReachedEmptyQueue = false

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
        self.sleep = { try await Task.sleep(for: $0) }
        self.beforeDisableCoordinatorTeardown = {}
        self.afterDisableAuthorizationTeardown = {}
    }

    init(
        historyStore: any PingHistoryStore,
        hostStore: any SharedHostStoring,
        boundary: any CloudSyncEngineBoundary,
        recordBuilder: any CloudSyncRecordBuilding,
        registrySuiteName: String,
        registryPersistenceObserver: @escaping @Sendable () -> Void = {},
        beforeDisableCoordinatorTeardown: @escaping @Sendable () async -> Void = {},
        afterDisableAuthorizationTeardown: @escaping @Sendable () async -> Void = {},
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        let versions = CloudSyncHostVersionRegistry(
            suiteName: registrySuiteName,
            onPersist: registryPersistenceObserver
        )
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
        self.sleep = sleep
        self.beforeDisableCoordinatorTeardown = beforeDisableCoordinatorTeardown
        self.afterDisableAuthorizationTeardown = afterDisableAuthorizationTeardown
    }

    func applyRemoteChanges(records: [CKRecord], deletions: [CloudSyncRemoteDeletion] = []) async {
        await receiver.apply(records: records, deletions: deletions)
    }

    public func setEnabled(_ enabled: Bool, hosts: [HostConfig]) async {
        requestedSyncEnabled = enabled
        requestedHosts = hosts
        lifecycleGeneration &+= 1
        let transition = lifecycleGeneration
        guard enabled else {
            let cancelledDrain = beginStoppingSampleDrain()
            await beforeDisableCoordinatorTeardown()
            await coordinator.setRecoveryHandler(nil)
            guard isCurrentTransition(transition) else { return }
            await coordinator.setAccountRecoveryAuthorizationHandler { false }
            guard isCurrentTransition(transition) else { return }
            await afterDisableAuthorizationTeardown()
            guard isCurrentTransition(transition) else { return }
            await coordinator.setAccountChangeHandler(nil)
            guard isCurrentTransition(transition) else { return }
            await coordinator.setEnabled(false, serviceLifecycleGeneration: transition)
            guard isCurrentTransition(transition) else { return }
            await cancelledDrain?.value
            return
        }
        await coordinator.setAccountChangeHandler { [weak self] in
            await self?.suspendSampleDrainForAccountChange()
        }
        guard isCurrentTransition(transition), requestedSyncEnabled else { return }
        await coordinator.setAccountRecoveryAuthorizationHandler { [weak self] in
            await self?.isSyncRequested() ?? false
        }
        guard isCurrentTransition(transition), requestedSyncEnabled else { return }
        await coordinator.setRecoveryHandler { [weak self] in
            await self?.resumeAfterCoordinatorAccountRecovery()
        }
        guard isCurrentTransition(transition), requestedSyncEnabled else { return }
        guard !isSyncEnabled else {
            await drainPendingHostDeletions()
            guard isCurrentLifecycle(transition) else { return }
            await uploadHosts(hosts)
            guard isCurrentLifecycle(transition) else { return }
            requestSampleDrain()
            return
        }
        await coordinator.setEnabled(enabled, serviceLifecycleGeneration: transition)
        let coordinatorStatus = await coordinator.status
        guard transition == lifecycleGeneration, coordinatorStatus == .idle else {
            guard transition == lifecycleGeneration else { return }
            isSyncEnabled = false
            return
        }
        isSyncEnabled = true
        await drainPendingHostDeletions()
        guard isCurrentLifecycle(transition) else { return }
        // start() fetches and applies remote changes first. Read the reconciled
        // shared store afterward so a remote edit/deletion is not overwritten by
        // the pre-fetch app snapshot captured when enable began.
        let pendingDeletionIDs = await versions.pendingDeletions()
        guard isCurrentLifecycle(transition) else { return }
        let reconciledHosts = (hostStore.load().state?.hosts ?? hosts).filter {
            !pendingDeletionIDs.contains($0.id)
        }
        await uploadInitialHosts(reconciledHosts)
        guard isCurrentLifecycle(transition) else { return }
        _ = await flushSampleDrain()
    }

    private func resumeAfterCoordinatorAccountRecovery() async {
        guard requestedSyncEnabled else { return }
        guard await coordinator.status == .idle, requestedSyncEnabled else { return }
        resetRetryState()
        let transition = lifecycleGeneration
        isSyncEnabled = true
        await drainPendingHostDeletions()
        guard isCurrentLifecycle(transition), requestedSyncEnabled else { return }
        let pendingDeletionIDs = await versions.pendingDeletions()
        guard isCurrentLifecycle(transition), requestedSyncEnabled else { return }
        let hosts = (hostStore.load().state?.hosts ?? requestedHosts).filter {
            !pendingDeletionIDs.contains($0.id)
        }
        await uploadInitialHosts(hosts)
        guard isCurrentLifecycle(transition), requestedSyncEnabled else { return }
        _ = await flushSampleDrain()
    }

    private func suspendSampleDrainForAccountChange() {
        guard requestedSyncEnabled else { return }
        lifecycleGeneration &+= 1
        isSyncEnabled = false
        drainGeneration &+= 1
        drainRequested = false
        cancelAccumulatedSampleDrain()
        resetRetryState()
        let task = drainTask
        drainTask = nil
        task?.cancel()
        sampleIDsAwaitingLocalAcknowledgement.removeAll(keepingCapacity: false)
        lastDrainReachedEmptyQueue = false
    }

    private func isSyncRequested() -> Bool {
        requestedSyncEnabled
    }

    @discardableResult
    public func uploadSamples(_ samples: [PingResult]) async -> Bool {
        _ = samples
        let drained = await flushSampleDrain()
        if drained {
            await drainPendingHostDeletions()
        }
        return drained
    }

    private enum SampleUploadResult {
        case confirmation(CloudSyncUploadConfirmation)
        case failure(CKError?)
    }

    private func uploadSampleBatch(_ samples: [PingResult]) async -> SampleUploadResult {
        do {
            guard let confirmation = try await coordinator.uploadWithConfirmation(samples: samples, hosts: []) else {
                return .failure(nil)
            }
            return .confirmation(confirmation)
        } catch let error as CKError {
            return .failure(error)
        } catch {
            return .failure(nil)
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

    func samplesDidBecomeDurable() {
        guard isSyncEnabled else { return }
        if drainTask != nil {
            drainRequested = true
            cancelAccumulatedSampleDrain()
            return
        }
        scheduleAccumulatedSampleDrain()
    }

    private func requestSampleDrain() {
        guard isSyncEnabled else { return }
        cancelAccumulatedSampleDrain()
        drainRequested = true
        guard drainTask == nil else { return }
        startSampleDrain()
    }

    private func startSampleDrain() {
        guard isSyncEnabled, drainTask == nil else { return }
        drainRequested = false
        lastDrainReachedEmptyQueue = false
        let generation = drainGeneration
        let retryEpoch = retryGeneration
        drainTask = Task { [weak self] in
            await self?.runSampleDrain(generation: generation, retryEpoch: retryEpoch)
        }
    }

    private func flushSampleDrain() async -> Bool {
        guard isSyncEnabled else { return false }
        requestSampleDrain()
        while let task = drainTask {
            await task.value
        }
        return lastDrainReachedEmptyQueue
    }

    private func beginStoppingSampleDrain() -> Task<Void, Never>? {
        isSyncEnabled = false
        drainGeneration &+= 1
        drainRequested = false
        cancelAccumulatedSampleDrain()
        resetRetryState()
        let task = drainTask
        drainTask = nil
        task?.cancel()
        sampleIDsAwaitingLocalAcknowledgement.removeAll(keepingCapacity: false)
        lastDrainReachedEmptyQueue = false
        return task
    }

    private func runSampleDrain(generation: UInt, retryEpoch: UInt) async {
        var reachedEmptyQueue = false
        var scheduledRetryDelay: Duration?
        var shouldStopDrain = false
        while isCurrentDrain(generation) {
            if !sampleIDsAwaitingLocalAcknowledgement.isEmpty {
                guard await acknowledgeConfirmedSamples(generation: generation) else { break }
                if scheduledRetryDelay != nil || shouldStopDrain { break }
            }
            guard isCurrentDrain(generation) else { break }
            guard let samples = try? await historyStore.unsyncedSamples(
                limit: Self.sampleUploadBatchLimit
            ) else {
                break
            }
            guard isCurrentDrain(generation) else { break }
            guard !samples.isEmpty else {
                reachedEmptyQueue = true
                break
            }
            let upload = await uploadSampleBatch(samples)
            guard isCurrentDrain(generation) else { break }
            switch upload {
            case let .failure(error):
                if let error, isRetryableSampleSaveError(error) {
                    scheduledRetryDelay = retryDelay(for: error)
                } else {
                    shouldStopDrain = true
                }
            case let .confirmation(confirmation):
                let requestedIDs = Set(samples.map(\.id))
                let confirmedIDs = Set(confirmation.confirmedRecordIDs.compactMap {
                    UUID(uuidString: $0.recordName)
                }).intersection(requestedIDs)
                let failedErrors = [UUID: CKError](uniqueKeysWithValues: confirmation.failedRecordSaveErrors.compactMap {
                    guard let id = UUID(uuidString: $0.key.recordName), requestedIDs.contains(id) else {
                        return nil
                    }
                    return (id, $0.value)
                })
                let terminalIDs = Set(failedErrors.compactMap { id, error in
                    sampleSaveDisposition(for: error) == .terminal ? id : nil
                })
                let transientErrors = failedErrors.values.filter {
                    sampleSaveDisposition(for: $0) == .retry
                }
                if failedErrors.values.contains(where: {
                    sampleSaveDisposition(for: $0) == .deferred
                }) {
                    shouldStopDrain = true
                }
                let unknownIDs = requestedIDs
                    .subtracting(confirmedIDs)
                    .subtracting(Set(failedErrors.keys))
                sampleIDsAwaitingLocalAcknowledgement = samples.map(\.id).filter {
                    confirmedIDs.contains($0) || terminalIDs.contains($0)
                }
                if !transientErrors.isEmpty || !unknownIDs.isEmpty {
                    var retryCandidates = transientErrors.map { retryDelay(for: $0) }
                    if !unknownIDs.isEmpty {
                        retryCandidates.append(Self.defaultSampleRetryDelay)
                    }
                    scheduledRetryDelay = retryCandidates.max()
                }
                if sampleIDsAwaitingLocalAcknowledgement.isEmpty { break }
            }

            if sampleIDsAwaitingLocalAcknowledgement.isEmpty,
               shouldStopDrain || scheduledRetryDelay != nil {
                break
            }
        }

        guard generation == drainGeneration else { return }
        lastDrainReachedEmptyQueue = reachedEmptyQueue
        drainTask = nil
        if reachedEmptyQueue {
            resetRetryState()
        }
        if drainRequested, isSyncEnabled {
            cancelScheduledSampleDrainRetry()
            startSampleDrain()
        } else if let scheduledRetryDelay,
                  isSyncEnabled,
                  retryEpoch == retryGeneration {
            consecutiveRetryCount = min(consecutiveRetryCount + 1, 6)
            scheduleSampleDrainRetry(
                after: scheduledRetryDelay,
                lifecycleGeneration: lifecycleGeneration,
                drainGeneration: generation
            )
        }
    }

    private func acknowledgeConfirmedSamples(generation: UInt) async -> Bool {
        let ids = sampleIDsAwaitingLocalAcknowledgement
        for attempt in 0..<Self.acknowledgementRetryLimit {
            guard isCurrentDrain(generation) else { return false }
            do {
                try await historyStore.markSamplesSynced(ids: ids)
                guard isCurrentDrain(generation),
                      sampleIDsAwaitingLocalAcknowledgement == ids else {
                    return false
                }
                sampleIDsAwaitingLocalAcknowledgement.removeAll(keepingCapacity: true)
                return true
            } catch {
                guard attempt + 1 < Self.acknowledgementRetryLimit else { return false }
                let delay = Duration.milliseconds(10 * (1 << attempt))
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return false
                }
            }
        }
        return false
    }

    private enum SampleSaveDisposition {
        case retry
        case terminal
        case deferred
    }

    private func sampleSaveDisposition(for error: CKError) -> SampleSaveDisposition {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .batchRequestFailed:
            .retry
        case .invalidArguments, .constraintViolation, .serverRejectedRequest,
             .assetFileNotFound, .permissionFailure:
            .terminal
        default:
            // Account/lifecycle and unfamiliar failures are not proof that a
            // record itself is poison. Keep it in the outbox without spinning;
            // a later lifecycle or durable-sample signal can try it again.
            .deferred
        }
    }

    private func isRetryableSampleSaveError(_ error: CKError) -> Bool {
        sampleSaveDisposition(for: error) == .retry
    }

    private func retryDelay(for error: CKError) -> Duration {
        let fallbackSeconds = min(1 << min(consecutiveRetryCount, 6), 60)
        guard let retryAfter = (error.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue,
              retryAfter.isFinite,
              retryAfter > 0 else {
            return .seconds(fallbackSeconds)
        }
        let milliseconds = min(
            max(retryAfter, Double(fallbackSeconds)) * 1_000,
            Self.maximumSampleRetryDelay
        )
        return .milliseconds(Int64(milliseconds.rounded(.up)))
    }

    private func scheduleSampleDrainRetry(
        after delay: Duration,
        lifecycleGeneration: UInt,
        drainGeneration: UInt
    ) {
        cancelScheduledSampleDrainRetry()
        retryGeneration &+= 1
        let retryID = retryGeneration
        retryTask = Task { [weak self] in
            do {
                try await self?.sleep(delay)
            } catch {
                return
            }
            await self?.fireSampleDrainRetry(
                retryID: retryID,
                lifecycleGeneration: lifecycleGeneration,
                drainGeneration: drainGeneration
            )
        }
    }

    private func fireSampleDrainRetry(
        retryID: UInt,
        lifecycleGeneration: UInt,
        drainGeneration: UInt
    ) {
        guard retryID == retryGeneration,
              lifecycleGeneration == self.lifecycleGeneration,
              drainGeneration == self.drainGeneration,
              isSyncEnabled,
              !Task.isCancelled else {
            return
        }
        retryTask = nil
        requestSampleDrain()
    }

    private func cancelScheduledSampleDrainRetry() {
        retryGeneration &+= 1
        retryTask?.cancel()
        retryTask = nil
    }

    private func resetRetryState() {
        consecutiveRetryCount = 0
        cancelScheduledSampleDrainRetry()
    }

    private func scheduleAccumulatedSampleDrain() {
        guard accumulationTask == nil else { return }
        accumulationGeneration &+= 1
        let accumulationID = accumulationGeneration
        let lifecycle = lifecycleGeneration
        let drain = drainGeneration
        accumulationTask = Task { [weak self] in
            do {
                try await self?.sleep(Self.sampleDrainAccumulationDelay)
            } catch {
                return
            }
            await self?.fireAccumulatedSampleDrain(
                accumulationID: accumulationID,
                lifecycleGeneration: lifecycle,
                drainGeneration: drain
            )
        }
    }

    private func fireAccumulatedSampleDrain(
        accumulationID: UInt,
        lifecycleGeneration: UInt,
        drainGeneration: UInt
    ) {
        guard accumulationID == accumulationGeneration,
              lifecycleGeneration == self.lifecycleGeneration,
              drainGeneration == self.drainGeneration,
              isSyncEnabled,
              !Task.isCancelled else {
            return
        }
        accumulationTask = nil
        requestSampleDrain()
    }

    private func cancelAccumulatedSampleDrain() {
        accumulationGeneration &+= 1
        accumulationTask?.cancel()
        accumulationTask = nil
    }

    private func isCurrentDrain(_ generation: UInt) -> Bool {
        isSyncEnabled && generation == drainGeneration && !Task.isCancelled
    }

    private func isCurrentLifecycle(_ generation: UInt) -> Bool {
        isSyncEnabled && generation == lifecycleGeneration
    }

    private func isCurrentTransition(_ generation: UInt) -> Bool {
        generation == lifecycleGeneration
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
        await service.samplesDidBecomeDurable()
    }

    public func append(_ results: [PingResult]) async {
        await destination.append(results)
        await service.samplesDidBecomeDurable()
    }

    public func appendAndWait(_ results: [PingResult]) async throws {
        try await destination.appendAndWait(results)
        await service.samplesDidBecomeDurable()
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

    public func prune(olderThan cutoff: Date) async { await destination.prune(olderThan: cutoff) }
    public func deleteAll() async { await destination.deleteAll() }
}
