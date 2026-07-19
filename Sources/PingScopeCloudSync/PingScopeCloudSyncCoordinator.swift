@preconcurrency import CloudKit
import Foundation
import PingScopeCore

public enum CloudSyncAccountAvailability: Equatable, Sendable {
    case privateAccount
    case unavailable
    case notPrivateAccount
}

public enum PingScopeCloudSyncStatus: Equatable, Sendable {
    case off
    case checkingAccount
    case idle
    case syncing
    case accountUnavailable
    case failed(String)
}

public struct CloudSyncHostVersion: Equatable, Sendable {
    public let config: HostConfig
    public let modifiedAt: Date

    public init(config: HostConfig, modifiedAt: Date) {
        self.config = config
        self.modifiedAt = modifiedAt
    }
}

public struct CloudSyncUploadConfirmation: @unchecked Sendable {
    public let requestedRecordIDs: Set<CKRecord.ID>
    public let confirmedRecordIDs: Set<CKRecord.ID>
    public let failedRecordSaveErrors: [CKRecord.ID: CKError]

    public init(
        requestedRecordIDs: Set<CKRecord.ID>,
        confirmedRecordIDs: Set<CKRecord.ID>,
        failedRecordSaveErrors: [CKRecord.ID: CKError] = [:]
    ) {
        self.requestedRecordIDs = requestedRecordIDs
        self.confirmedRecordIDs = confirmedRecordIDs
        self.failedRecordSaveErrors = failedRecordSaveErrors
    }

    public init(confirming records: [CKRecord]) {
        let recordIDs = Set(records.map(\.recordID))
        self.init(requestedRecordIDs: recordIDs, confirmedRecordIDs: recordIDs)
    }

    public var allRecordsConfirmed: Bool {
        requestedRecordIDs.isSubset(of: confirmedRecordIDs)
    }
}

public protocol CloudSyncEngineBoundary: Sendable {
    func accountAvailability() async throws -> CloudSyncAccountAvailability
    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async
    func start() async throws
    func stop() async
    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation
}

public extension CloudSyncEngineBoundary {
    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async {
        _ = handler
    }
}

public protocol CloudSyncRecordBuilding: Sendable {
    func sampleRecord(from sample: PingResult) async -> CKRecord
    func hostRecord(from host: CloudSyncHostVersion) async throws -> CKRecord
}

public struct DefaultCloudSyncRecordBuilder: CloudSyncRecordBuilding, Sendable {
    public init() {}

    public func sampleRecord(from sample: PingResult) async -> CKRecord {
        PingSampleRecordMapper.record(from: sample)
    }

    public func hostRecord(from host: CloudSyncHostVersion) async throws -> CKRecord {
        try MonitoredHostRecordMapper.record(from: host.config, modifiedAt: host.modifiedAt)
    }
}

/// Owns the opt-in privacy gate. Record materialization happens only after both
/// the persisted user preference and private-account availability are confirmed.
public actor PingScopeCloudSyncCoordinator {
    public private(set) var status: PingScopeCloudSyncStatus = .off

    private let boundary: any CloudSyncEngineBoundary
    private let recordBuilder: any CloudSyncRecordBuilding
    private var isEnabled = false
    private var hasStarted = false
    private var lifecycleGeneration: UInt = 0
    private var latestServiceLifecycleGeneration: UInt = 0
    private var nextLifecycleWorkID: UInt = 0
    private var activeLifecycleWork: LifecycleWork?
    private var nextBoundaryStopID: UInt = 0
    private var activeBoundaryStop: BoundaryStop?
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var accountRecoveryAuthorizationHandler: (@Sendable () async -> Bool)?
    private var recoveryHandler: (@Sendable () async -> Void)?

    private struct BoundaryStop {
        let id: UInt
        let task: Task<Void, Never>
    }

    private struct LifecycleWork {
        let id: UInt
        let task: Task<Void, Never>
    }

    public init(
        boundary: any CloudSyncEngineBoundary,
        recordBuilder: any CloudSyncRecordBuilding = DefaultCloudSyncRecordBuilder()
    ) {
        self.boundary = boundary
        self.recordBuilder = recordBuilder
    }

    func setRecoveryHandler(_ handler: (@Sendable () async -> Void)?) {
        recoveryHandler = handler
    }

    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) {
        accountChangeHandler = handler
    }

    func setAccountRecoveryAuthorizationHandler(
        _ handler: (@Sendable () async -> Bool)?
    ) {
        accountRecoveryAuthorizationHandler = handler
    }

    public func setEnabled(_ enabled: Bool) async {
        await setEnabled(enabled, serviceLifecycleGeneration: nil)
    }

    func setEnabled(_ enabled: Bool, serviceLifecycleGeneration: UInt?) async {
        if let serviceLifecycleGeneration {
            guard serviceLifecycleGeneration >= latestServiceLifecycleGeneration else { return }
            latestServiceLifecycleGeneration = serviceLifecycleGeneration
        }
        if enabled,
           isEnabled,
           !hasStarted,
           let activeLifecycleWork {
            await activeLifecycleWork.task.value
            return
        }
        guard !enabled || !isEnabled || !hasStarted else { return }
        lifecycleGeneration &+= 1
        let transition = lifecycleGeneration
        guard enabled else {
            isEnabled = false
            hasStarted = false
            accountChangeHandler = nil
            // Register the complete boundary retirement before the first
            // suspension. A later enable waits for this owner before it can
            // install its handler or start a new boundary.
            let stop = beginBoundaryStop(clearingAccountChangeHandler: true)
            await stop.task.value
            finishBoundaryStop(id: stop.id)
            guard transition == lifecycleGeneration else { return }
            status = .off
            return
        }

        guard !isEnabled || !hasStarted else { return }
        if let stop = activeBoundaryStop {
            await stop.task.value
            finishBoundaryStop(id: stop.id)
            guard transition == lifecycleGeneration else { return }
        }
        isEnabled = true
        let work = beginLifecycleWork { [weak self] workID in
            await self?.performEnable(transition: transition, workID: workID)
        }
        await work.task.value
    }

    private func recoverAfterAccountChange() async {
        guard await accountRecoveryAuthorizationHandler?() ?? true else { return }
        lifecycleGeneration &+= 1
        let transition = lifecycleGeneration
        guard isEnabled else { return }
        hasStarted = false
        let work = beginLifecycleWork { [weak self] workID in
            await self?.performRecovery(transition: transition, workID: workID)
        }
        await work.task.value
    }

    private func performEnable(transition: UInt, workID: UInt) async {
        defer { finishLifecycleWork(id: workID) }
        await boundary.setAccountChangeHandler { [weak self] in
            await self?.recoverAfterAccountChange()
        }
        guard transition == lifecycleGeneration, isEnabled else { return }
        _ = await startAfterAccountRevalidation(transition: transition)
    }

    private func performRecovery(transition: UInt, workID: UInt) async {
        defer { finishLifecycleWork(id: workID) }
        await accountChangeHandler?()
        guard transition == lifecycleGeneration, isEnabled else { return }
        status = .checkingAccount
        let stop = beginBoundaryStop()
        await stop.task.value
        finishBoundaryStop(id: stop.id)
        guard transition == lifecycleGeneration, isEnabled else { return }
        guard await startAfterAccountRevalidation(transition: transition) else { return }
        await recoveryHandler?()
    }

    private func beginLifecycleWork(
        _ operation: @escaping @Sendable (UInt) async -> Void
    ) -> LifecycleWork {
        nextLifecycleWorkID &+= 1
        let id = nextLifecycleWorkID
        let work = LifecycleWork(
            id: id,
            task: Task { await operation(id) }
        )
        activeLifecycleWork = work
        return work
    }

    private func finishLifecycleWork(id: UInt) {
        guard activeLifecycleWork?.id == id else { return }
        activeLifecycleWork = nil
    }

    @discardableResult
    private func startAfterAccountRevalidation(transition: UInt) async -> Bool {
        status = .checkingAccount
        let availability: CloudSyncAccountAvailability
        do {
            availability = try await boundary.accountAvailability()
        } catch {
            guard transition == lifecycleGeneration else { return false }
            hasStarted = false
            status = .failed(String(describing: error))
            return false
        }
        guard availability == .privateAccount else {
            guard transition == lifecycleGeneration else { return false }
            hasStarted = false
            status = .accountUnavailable
            return false
        }
        guard transition == lifecycleGeneration, isEnabled else { return false }
        do {
            try await boundary.start()
            guard transition == lifecycleGeneration, isEnabled else {
                if !isEnabled {
                    let stop = beginBoundaryStop()
                    await stop.task.value
                    finishBoundaryStop(id: stop.id)
                }
                return false
            }
            hasStarted = true
            status = .idle
            return true
        } catch {
            guard transition == lifecycleGeneration else { return false }
            hasStarted = false
            status = .failed(String(describing: error))
            return false
        }
    }

    private func beginBoundaryStop(clearingAccountChangeHandler: Bool = false) -> BoundaryStop {
        if let activeBoundaryStop { return activeBoundaryStop }
        nextBoundaryStopID &+= 1
        let stop = BoundaryStop(
            id: nextBoundaryStopID,
            task: Task { [boundary] in
                if clearingAccountChangeHandler {
                    await boundary.setAccountChangeHandler(nil)
                }
                await boundary.stop()
            }
        )
        activeBoundaryStop = stop
        return stop
    }

    private func finishBoundaryStop(id: UInt) {
        guard activeBoundaryStop?.id == id else { return }
        activeBoundaryStop = nil
    }

    public func upload(
        samples: [PingResult],
        hosts: [CloudSyncHostVersion],
        deletions: [CKRecord.ID] = []
    ) async throws -> Bool {
        try await uploadWithConfirmation(
            samples: samples,
            hosts: hosts,
            deletions: deletions
        )?.allRecordsConfirmed == true
    }

    public func uploadWithConfirmation(
        samples: [PingResult],
        hosts: [CloudSyncHostVersion],
        deletions: [CKRecord.ID] = []
    ) async throws -> CloudSyncUploadConfirmation? {
        // This guard deliberately precedes every mapper call: OFF means no
        // CKRecord is created, queued, or uploaded.
        guard isEnabled, hasStarted else { return nil }
        let uploadLifecycleGeneration = lifecycleGeneration
        status = .syncing
        do {
            var records: [CKRecord] = []
            records.reserveCapacity(samples.count + hosts.count)
            for sample in samples {
                guard uploadLifecycleGeneration == lifecycleGeneration,
                      isEnabled,
                      hasStarted else { return nil }
                records.append(await recordBuilder.sampleRecord(from: sample))
                guard uploadLifecycleGeneration == lifecycleGeneration,
                      isEnabled,
                      hasStarted else { return nil }
            }
            for host in hosts {
                guard uploadLifecycleGeneration == lifecycleGeneration,
                      isEnabled,
                      hasStarted else { return nil }
                records.append(try await recordBuilder.hostRecord(from: host))
                guard uploadLifecycleGeneration == lifecycleGeneration,
                      isEnabled,
                      hasStarted else { return nil }
            }
            guard uploadLifecycleGeneration == lifecycleGeneration,
                  isEnabled,
                  hasStarted else { return nil }
            let confirmation = try await boundary.upload(records: records, deletions: deletions)
            guard uploadLifecycleGeneration == lifecycleGeneration,
                  isEnabled,
                  hasStarted else {
                return nil
            }
            status = .idle
            return confirmation
        } catch {
            restoreStatusAfterFailedUpload(lifecycleGeneration: uploadLifecycleGeneration)
            throw error
        }
    }

    private func restoreStatusAfterFailedUpload(lifecycleGeneration: UInt) {
        guard lifecycleGeneration == self.lifecycleGeneration else { return }
        if isEnabled, hasStarted {
            status = .idle
        } else if isEnabled {
            status = .checkingAccount
        } else {
            status = .off
        }
    }
}

public enum CloudSyncConflictResolver {
    /// Last-modified wins. Local wins exact ties so retry order cannot oscillate.
    public static func resolve(
        local: CloudSyncHostVersion,
        remote: CloudSyncHostVersion
    ) -> CloudSyncHostVersion {
        remote.modifiedAt > local.modifiedAt ? remote : local
    }
}

public enum CloudSyncRemoteChangeApplier {
    public static func apply(
        sampleRecords: [CKRecord],
        to store: any PingHistoryStore
    ) async throws {
        try await store.upsertRemoteSamples(sampleRecords.compactMap(PingSampleRecordMapper.pingResult(from:)))
    }

    public static func deleteSampleRecordIDs(
        _ recordIDs: [CKRecord.ID],
        from store: any PingHistoryStore
    ) async throws {
        try await store.deleteSamples(ids: recordIDs.compactMap { UUID(uuidString: $0.recordName) })
    }
}
