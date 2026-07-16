@preconcurrency import CloudKit
import Foundation

public struct CloudSyncRemoteDeletion: Equatable, Sendable {
    public let recordID: CKRecord.ID
    public let recordType: String

    public init(recordID: CKRecord.ID, recordType: String) {
        self.recordID = recordID
        self.recordType = recordType
    }
}

/// The live CloudKit edge. CloudKit resources are created lazily, only after
/// the coordinator has passed the opt-in gate and checks account availability.
public actor CKSyncEngineBoundary: CloudSyncEngineBoundary {
    public typealias RemoteChangeHandler = @Sendable ([CKRecord], [CloudSyncRemoteDeletion]) async -> Void

    private let containerIdentifier: String
    private let stateKey: String
    private let onRemoteChanges: RemoteChangeHandler
    private var resources: Resources?
    private var engine: CKSyncEngine?

    private struct Resources {
        let container: CKContainer
        let database: CKDatabase
        let delegate: PingScopeCKSyncEngineDelegate
    }

    public init(
        containerIdentifier: String = PingScopeCloudKitModel.containerIdentifier,
        stateKey: String = "PingScope.CloudSync.CKSyncEngineState",
        onRemoteChanges: @escaping RemoteChangeHandler = { _, _ in }
    ) {
        self.containerIdentifier = containerIdentifier
        self.stateKey = stateKey
        self.onRemoteChanges = onRemoteChanges
    }

    public func accountAvailability() async -> CloudSyncAccountAvailability {
        let resources = ensureResources()
        do {
            return try await resources.container.accountStatus() == .available ? .privateAccount : .unavailable
        } catch {
            return .unavailable
        }
    }

    public func start() async throws {
        guard engine == nil else { return }
        let resources = ensureResources()
        let delegate = resources.delegate
        await delegate.setActive(true)
        var configuration = CKSyncEngine.Configuration(
            database: resources.database,
            stateSerialization: delegate.restoredStateSerialization(),
            delegate: delegate
        )
        // The engine exists only while the explicit opt-in is enabled. While it
        // exists, automatic scheduling supplies push-driven fetches and CloudKit
        // backoff; stop() cancels and releases it immediately when opt-in ends.
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: PingScopeCloudKitModel.zoneID))
        ])
        do {
            try await engine.sendChanges()
            guard self.engine === engine, await delegate.isActive() else {
                await engine.cancelOperations()
                return
            }
            try await engine.fetchChanges()
        } catch {
            await engine.cancelOperations()
            self.engine = nil
            await delegate.setActive(false)
            throw error
        }
    }

    public func stop() async {
        guard let resources else { return }
        await resources.delegate.setActive(false)
        guard let engine else { return }
        await engine.cancelOperations()
        self.engine = nil
    }

    public func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws {
        guard let engine, let resources, await resources.delegate.isActive() else {
            throw CloudSyncBoundaryError.inactive
        }
        await resources.delegate.stage(records: records)
        await resources.delegate.prepare(deletions: deletions)
        engine.state.add(pendingRecordZoneChanges:
            records.map { .saveRecord($0.recordID) }
            + deletions.map(CKSyncEngine.PendingRecordZoneChange.deleteRecord)
        )
        try await engine.sendChanges()
        if let failure = await resources.delegate.deleteFailure(for: deletions) {
            throw failure
        }
    }

    private func ensureResources() -> Resources {
        if let resources { return resources }
        let container = CKContainer(identifier: containerIdentifier)
        let resources = Resources(
            container: container,
            database: container.privateCloudDatabase,
            delegate: PingScopeCKSyncEngineDelegate(
                stateKey: stateKey,
                onRemoteChanges: onRemoteChanges
            )
        )
        self.resources = resources
        return resources
    }
}

private enum CloudSyncBoundaryError: Error {
    case inactive
}

private actor PingScopeCKSyncEngineDelegateState {
    private var active = false
    private var stagedRecords: [CKRecord.ID: CKRecord] = [:]
    private var failedDeletions: [CKRecord.ID: CKError] = [:]

    func setActive(_ value: Bool) { active = value }

    func stage(_ records: [CKRecord]) {
        guard active else { return }
        for record in records { stagedRecords[record.recordID] = record }
    }

    func record(for id: CKRecord.ID) -> CKRecord? {
        guard active else { return nil }
        return stagedRecords[id]
    }

    func remove(_ ids: [CKRecord.ID]) {
        for id in ids { stagedRecords[id] = nil }
    }

    func prepare(deletions: [CKRecord.ID]) {
        for id in deletions { failedDeletions[id] = nil }
    }

    func recordDeleteFailures(_ failures: [CKRecord.ID: CKError]) {
        for (id, error) in failures { failedDeletions[id] = error }
    }

    func deleteFailure(for ids: [CKRecord.ID]) -> CKError? {
        ids.lazy.compactMap { self.failedDeletions[$0] }.first
    }

    func isActive() -> Bool { active }
}

private final class PingScopeCKSyncEngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private let state = PingScopeCKSyncEngineDelegateState()
    private let stateKey: String
    private let onRemoteChanges: CKSyncEngineBoundary.RemoteChangeHandler

    init(
        stateKey: String,
        onRemoteChanges: @escaping CKSyncEngineBoundary.RemoteChangeHandler
    ) {
        self.stateKey = stateKey
        self.onRemoteChanges = onRemoteChanges
    }

    func restoredStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func setActive(_ active: Bool) async { await state.setActive(active) }
    func isActive() async -> Bool { await state.isActive() }
    func stage(records: [CKRecord]) async { await state.stage(records) }
    func prepare(deletions: [CKRecord.ID]) async { await state.prepare(deletions: deletions) }
    func deleteFailure(for ids: [CKRecord.ID]) async -> CKError? { await state.deleteFailure(for: ids) }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard await state.isActive() else { return }
        switch event {
        case let .stateUpdate(update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey)
            }
        case let .fetchedRecordZoneChanges(changes):
            let records = changes.modifications.map(\.record)
            let deletions = changes.deletions.map {
                CloudSyncRemoteDeletion(recordID: $0.recordID, recordType: $0.recordType)
            }
            await onRemoteChanges(records, deletions)
        case let .sentRecordZoneChanges(changes):
            await state.remove(changes.savedRecords.map(\.recordID) + changes.deletedRecordIDs)
            let confirmedAbsent = changes.failedRecordDeletes.compactMap { recordID, error in
                error.code == .unknownItem ? recordID : nil
            }
            if !confirmedAbsent.isEmpty {
                syncEngine.state.remove(pendingRecordZoneChanges: confirmedAbsent.map {
                    .deleteRecord($0)
                })
            }
            await state.recordDeleteFailures(
                changes.failedRecordDeletes.filter { $0.value.code != .unknownItem }
            )
        case .accountChange:
            // Account switches invalidate private-database ownership and all
            // in-flight work. A later explicit enable/account refresh creates
            // a fresh engine after the coordinator rechecks availability.
            await state.setActive(false)
            await syncEngine.cancelOperations()
        case let .fetchedDatabaseChanges(changes):
            if changes.deletions.contains(where: { $0.zoneID == PingScopeCloudKitModel.zoneID }) {
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: PingScopeCloudKitModel.zoneID))
                ])
                syncEngine.state.hasPendingUntrackedChanges = true
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard await state.isActive() else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [state] recordID in
            await state.record(for: recordID)
        }
    }
}
