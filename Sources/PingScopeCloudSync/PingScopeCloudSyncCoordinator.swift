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

public protocol CloudSyncEngineBoundary: Sendable {
    func accountAvailability() async -> CloudSyncAccountAvailability
    func start() async throws
    func stop() async
    func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws
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

    public init(
        boundary: any CloudSyncEngineBoundary,
        recordBuilder: any CloudSyncRecordBuilding = DefaultCloudSyncRecordBuilder()
    ) {
        self.boundary = boundary
        self.recordBuilder = recordBuilder
    }

    public func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            isEnabled = false
            // Always stop the boundary, including while account/zone startup is
            // suspended. This closes the enable-then-immediate-disable race.
            await boundary.stop()
            hasStarted = false
            status = .off
            return
        }

        guard !isEnabled || !hasStarted else { return }
        isEnabled = true
        status = .checkingAccount
        guard await boundary.accountAvailability() == .privateAccount else {
            isEnabled = false
            hasStarted = false
            status = .accountUnavailable
            return
        }
        guard isEnabled else { return }
        do {
            try await boundary.start()
            guard isEnabled else {
                await boundary.stop()
                return
            }
            hasStarted = true
            status = .idle
        } catch {
            hasStarted = false
            status = .failed(String(describing: error))
        }
    }

    public func upload(
        samples: [PingResult],
        hosts: [CloudSyncHostVersion],
        deletions: [CKRecord.ID] = []
    ) async throws -> Bool {
        // This guard deliberately precedes every mapper call: OFF means no
        // CKRecord is created, queued, or uploaded.
        guard isEnabled, hasStarted else { return false }
        status = .syncing
        var records: [CKRecord] = []
        records.reserveCapacity(samples.count + hosts.count)
        for sample in samples {
            guard isEnabled, hasStarted else { return false }
            records.append(await recordBuilder.sampleRecord(from: sample))
        }
        for host in hosts {
            guard isEnabled, hasStarted else { return false }
            records.append(try await recordBuilder.hostRecord(from: host))
        }
        guard isEnabled, hasStarted else { return false }
        try await boundary.upload(records: records, deletions: deletions)
        status = .idle
        return true
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
