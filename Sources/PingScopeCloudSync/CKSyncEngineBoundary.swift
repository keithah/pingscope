@preconcurrency import CloudKit
import Foundation
import PingScopeCore

struct CloudKitEngineHandle: Hashable, Sendable {
    fileprivate let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

protocol CloudKitEngineHosting: Sendable {
    func prepareResources()
    func accountAvailability() async -> CloudSyncAccountAvailability
    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) -> CloudKitEngineHandle
    func addPendingDatabaseChanges(
        _ changes: [CKSyncEngine.PendingDatabaseChange],
        to handle: CloudKitEngineHandle
    )
    func addPendingRecordZoneChanges(
        _ changes: [CKSyncEngine.PendingRecordZoneChange],
        to handle: CloudKitEngineHandle
    )
    func sendChanges(on handle: CloudKitEngineHandle) async throws
    func fetchChanges(on handle: CloudKitEngineHandle) async throws
    func cancelOperations(on handle: CloudKitEngineHandle) async
    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws
    func releaseEngine(_ handle: CloudKitEngineHandle)
}

private final class LiveCloudKitEngineHost: CloudKitEngineHosting, @unchecked Sendable {
    private let containerIdentifier: String
    private let lock = NSLock()
    private var resources: Resources?
    private var engines: [CloudKitEngineHandle: CKSyncEngine] = [:]

    private struct Resources {
        let container: CKContainer
        let database: CKDatabase
    }

    init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    func prepareResources() {
        _ = ensureResources()
    }

    func accountAvailability() async -> CloudSyncAccountAvailability {
        let resources = ensureResources()
        do {
            return try await resources.container.accountStatus() == .available ? .privateAccount : .unavailable
        } catch {
            return .unavailable
        }
    }

    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) -> CloudKitEngineHandle {
        let resources = ensureResources()
        var configuration = CKSyncEngine.Configuration(
            database: resources.database,
            stateSerialization: stateSerialization,
            delegate: delegate
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = subscriptionID
        let engine = CKSyncEngine(configuration)
        let handle = CloudKitEngineHandle()
        lock.withLock { engines[handle] = engine }
        return handle
    }

    func addPendingDatabaseChanges(
        _ changes: [CKSyncEngine.PendingDatabaseChange],
        to handle: CloudKitEngineHandle
    ) {
        engine(for: handle)?.state.add(pendingDatabaseChanges: changes)
    }

    func addPendingRecordZoneChanges(
        _ changes: [CKSyncEngine.PendingRecordZoneChange],
        to handle: CloudKitEngineHandle
    ) {
        engine(for: handle)?.state.add(pendingRecordZoneChanges: changes)
    }

    func sendChanges(on handle: CloudKitEngineHandle) async throws {
        guard let engine = engine(for: handle) else { throw CloudSyncBoundaryError.inactive }
        try await engine.sendChanges()
    }

    func fetchChanges(on handle: CloudKitEngineHandle) async throws {
        guard let engine = engine(for: handle) else { throw CloudSyncBoundaryError.inactive }
        try await engine.fetchChanges()
    }

    func cancelOperations(on handle: CloudKitEngineHandle) async {
        guard let engine = engine(for: handle) else { return }
        await engine.cancelOperations()
    }

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws {
        guard let database = lock.withLock({ resources?.database }) else { return }
        _ = try await database.deleteSubscription(withID: subscriptionID)
    }

    func releaseEngine(_ handle: CloudKitEngineHandle) {
        lock.withLock { engines[handle] = nil }
    }

    private func ensureResources() -> Resources {
        lock.withLock {
            if let resources { return resources }
            let container = CKContainer(identifier: containerIdentifier)
            let resources = Resources(
                container: container,
                database: container.privateCloudDatabase
            )
            self.resources = resources
            return resources
        }
    }

    private func engine(for handle: CloudKitEngineHandle) -> CKSyncEngine? {
        lock.withLock { engines[handle] }
    }
}

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

    private let stateKey: String
    private let subscriptionID: CKSubscription.ID
    private let engineHost: any CloudKitEngineHosting
    private let onRemoteChanges: RemoteChangeHandler
    private var resourcesInitialized = false
    private var delegate: PingScopeCKSyncEngineDelegate?
    private var engineHandle: CloudKitEngineHandle?

    public init(
        containerIdentifier: String = PingScopeCloudKitModel.containerIdentifier,
        stateKey: String = "PingScope.CloudSync.CKSyncEngineState",
        subscriptionID: CKSubscription.ID = "PingScope.CloudSync.PrivateDatabase",
        onRemoteChanges: @escaping RemoteChangeHandler = { _, _ in }
    ) {
        self.stateKey = stateKey
        self.subscriptionID = subscriptionID
        self.engineHost = LiveCloudKitEngineHost(containerIdentifier: containerIdentifier)
        self.onRemoteChanges = onRemoteChanges
    }

    init(
        engineHost: any CloudKitEngineHosting,
        stateKey: String,
        subscriptionID: CKSubscription.ID,
        onRemoteChanges: @escaping RemoteChangeHandler = { _, _ in }
    ) {
        self.stateKey = stateKey
        self.subscriptionID = subscriptionID
        self.engineHost = engineHost
        self.onRemoteChanges = onRemoteChanges
    }

    public func accountAvailability() async -> CloudSyncAccountAvailability {
        engineHost.prepareResources()
        resourcesInitialized = true
        return await engineHost.accountAvailability()
    }

    public func start() async throws {
        guard engineHandle == nil else { return }
        engineHost.prepareResources()
        resourcesInitialized = true
        let delegate = ensureDelegate()
        await delegate.setActive(true)
        let engineHandle = engineHost.createEngine(
            stateSerialization: delegate.restoredStateSerialization(),
            delegate: delegate,
            subscriptionID: subscriptionID
        )
        self.engineHandle = engineHandle

        engineHost.addPendingDatabaseChanges([
            .saveZone(CKRecordZone(zoneID: PingScopeCloudKitModel.zoneID))
        ], to: engineHandle)
        do {
            try await engineHost.sendChanges(on: engineHandle)
            guard self.engineHandle == engineHandle, await delegate.isActive() else {
                await engineHost.cancelOperations(on: engineHandle)
                return
            }
            try await engineHost.fetchChanges(on: engineHandle)
        } catch {
            await engineHost.cancelOperations(on: engineHandle)
            engineHost.releaseEngine(engineHandle)
            self.engineHandle = nil
            await delegate.setActive(false)
            throw error
        }
    }

    public func stop() async {
        guard resourcesInitialized else { return }
        if let delegate {
            await delegate.setActive(false)
        }
        if let engineHandle {
            await engineHost.cancelOperations(on: engineHandle)
        }
        do {
            try await tearDownSubscriptions()
        } catch {
            DebugLog.write("CloudKit subscription teardown failed: \(error.localizedDescription)")
        }
        if let engineHandle {
            engineHost.releaseEngine(engineHandle)
        }
        self.engineHandle = nil
    }

    public func tearDownSubscriptions() async throws {
        // Do not create CloudKit resources on the disabled path. If sync never
        // started, there cannot be a PingScope-owned subscription to remove.
        guard resourcesInitialized else { return }

        do {
            try await engineHost.deleteSubscription(withID: subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already absent is the idempotent success state.
        }
    }

    public func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws {
        guard let engineHandle, let delegate, await delegate.isActive() else {
            throw CloudSyncBoundaryError.inactive
        }
        await delegate.stage(records: records)
        await delegate.prepare(deletions: deletions)
        engineHost.addPendingRecordZoneChanges(
            records.map { .saveRecord($0.recordID) }
                + deletions.map(CKSyncEngine.PendingRecordZoneChange.deleteRecord),
            to: engineHandle
        )
        try await engineHost.sendChanges(on: engineHandle)
        if let failure = await delegate.deleteFailure(for: deletions) {
            throw failure
        }
    }

    private func ensureDelegate() -> PingScopeCKSyncEngineDelegate {
        if let delegate { return delegate }
        let delegate = PingScopeCKSyncEngineDelegate(
            stateKey: stateKey,
            onRemoteChanges: onRemoteChanges
        )
        self.delegate = delegate
        return delegate
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
