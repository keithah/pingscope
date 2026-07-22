@preconcurrency import CloudKit
import Foundation
import PingScopeCore
import PingScopeObjCExceptionBoundary
#if os(macOS)
import Security
#endif

enum CloudSyncBoundaryError: Error, Equatable {
    case inactive
    case missingContainerEntitlement(String)
    case accountStatusTimedOut
}

private enum CloudKitAccountStatusOutcome: @unchecked Sendable {
    case status(CKAccountStatus)
    case failure(Error)
    case timedOut
    case cancelled
}

private actor CloudKitAccountStatusRace {
    private var outcome: CloudKitAccountStatusOutcome?
    private var waiters: [CheckedContinuation<CloudKitAccountStatusOutcome, Never>] = []

    func finish(_ outcome: CloudKitAccountStatusOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume(returning: outcome) }
    }

    func value() async -> CloudKitAccountStatusOutcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

struct CloudKitEngineHandle: Hashable, Sendable {
    fileprivate let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

protocol CloudKitEngineHosting: Sendable {
    func prepareResources() throws
    func accountAvailability() async throws -> CloudSyncAccountAvailability
    func setAccountChangeHandler(_ handler: (@concurrent @Sendable () async -> Void)?)
    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) throws -> CloudKitEngineHandle
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

protocol CloudKitContainerProviding: Sendable {
    func defaultContainer(for identifier: String) throws -> CKContainer
}

struct DefaultCloudKitContainerProvider: CloudKitContainerProviding, @unchecked Sendable {
    private static let containerIdentifiersEntitlement = "com.apple.developer.icloud-container-identifiers"
    private static let bundledContainerIdentifiersKey = "PingScopeICloudContainerIdentifiers"

    private let entitledContainerIdentifiers: () -> [String]
    private let makeDefaultContainer: () -> CKContainer

    init(
        entitledContainerIdentifiers: @escaping () -> [String] = Self.currentProcessContainerIdentifiers,
        makeDefaultContainer: @escaping () -> CKContainer = { CKContainer.default() }
    ) {
        self.entitledContainerIdentifiers = entitledContainerIdentifiers
        self.makeDefaultContainer = makeDefaultContainer
    }

    func defaultContainer(for identifier: String) throws -> CKContainer {
        guard entitledContainerIdentifiers().contains(identifier) else {
            throw CloudSyncBoundaryError.missingContainerEntitlement(identifier)
        }
        guard let container = PingScopePerformCatchingObjCException({ makeDefaultContainer() }) as? CKContainer else {
            throw CloudSyncBoundaryError.missingContainerEntitlement(identifier)
        }
        guard container.containerIdentifier == identifier else {
            throw CloudSyncBoundaryError.missingContainerEntitlement(identifier)
        }
        return container
    }

    private static func currentProcessContainerIdentifiers() -> [String] {
        #if targetEnvironment(simulator)
        // Simulator builds are ad-hoc signed without the app's iCloud
        // entitlement. Calling CKContainer.default() here raises CKException.
        return []
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  containerIdentifiersEntitlement as CFString,
                  nil
              ) else {
            return []
        }
        return value as? [String] ?? []
        #else
        // iOS does not expose SecTask. Couple container construction to the
        // signed target's explicit bundle declaration instead of iCloud Drive.
        return Bundle.main.object(forInfoDictionaryKey: bundledContainerIdentifiersKey) as? [String] ?? []
        #endif
    }
}

private final class CloudKitAccountChangeObserver: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var handler: (@concurrent @Sendable () async -> Void)?
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.notify()
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func setHandler(_ handler: (@concurrent @Sendable () async -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    private func notify() {
        guard let handler = lock.withLock({ handler }) else { return }
        Task { await handler() }
    }
}

final class LiveCloudKitEngineHost: CloudKitEngineHosting, @unchecked Sendable {
    private let containerIdentifier: String
    private let containerProvider: any CloudKitContainerProviding
    private let injectedAccountStatus: (@Sendable () async throws -> CKAccountStatus)?
    private let accountStatusTimeout: Duration
    private let accountChangeObserver = CloudKitAccountChangeObserver()
    private let lock = NSLock()
    private var resources: Resources?
    private var engines: [CloudKitEngineHandle: CKSyncEngine] = [:]

    private struct Resources {
        let container: CKContainer
        let database: CKDatabase
    }

    init(
        containerIdentifier: String,
        containerProvider: any CloudKitContainerProviding = DefaultCloudKitContainerProvider(),
        accountStatus: (@Sendable () async throws -> CKAccountStatus)? = nil,
        accountStatusTimeout: Duration = .seconds(10)
    ) {
        self.containerIdentifier = containerIdentifier
        self.containerProvider = containerProvider
        self.injectedAccountStatus = accountStatus
        self.accountStatusTimeout = accountStatusTimeout
    }

    func prepareResources() throws {
        _ = try ensureResources()
    }

    func accountAvailability() async throws -> CloudSyncAccountAvailability {
        let operation: @Sendable () async throws -> CKAccountStatus
        if let injectedAccountStatus {
            operation = injectedAccountStatus
        } else {
            let resources = try ensureResources()
            operation = { try await resources.container.accountStatus() }
        }
        let status = try await accountStatusWithRetry(operation)
        return status == .available ? .privateAccount : .unavailable
    }

    private func accountStatusWithRetry(
        _ operation: @escaping @Sendable () async throws -> CKAccountStatus
    ) async throws -> CKAccountStatus {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await accountStatusWithTimeout(operation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < 2, Self.isRetryableAccountStatusError(error) else { throw error }
                let retryAfter = (error as? CKError)?
                    .userInfo[CKErrorRetryAfterKey] as? TimeInterval
                let exponential = 0.1 * Double(1 << attempt)
                let delay = retryAfter ?? exponential + Double.random(in: 0...(exponential * 0.2))
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw lastError ?? CloudSyncBoundaryError.accountStatusTimedOut
    }

    private func accountStatusWithTimeout(
        _ operation: @escaping @Sendable () async throws -> CKAccountStatus
    ) async throws -> CKAccountStatus {
        let race = CloudKitAccountStatusRace()
        let operationTask = Task {
            do {
                await race.finish(.status(try await operation()))
            } catch is CancellationError {
                await race.finish(.cancelled)
            } catch {
                await race.finish(.failure(error))
            }
        }
        let timeout = accountStatusTimeout
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                await race.finish(.timedOut)
            } catch {
                // The operation completed or the caller cancelled.
            }
        }
        let outcome = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task { await race.finish(.cancelled) }
        }
        operationTask.cancel()
        timeoutTask.cancel()
        switch outcome {
        case let .status(status): return status
        case let .failure(error): throw error
        case .timedOut: throw CloudSyncBoundaryError.accountStatusTimedOut
        case .cancelled: throw CancellationError()
        }
    }

    private static func isRetryableAccountStatusError(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .networkFailure, .networkUnavailable, .requestRateLimited,
             .serviceUnavailable, .zoneBusy:
            return true
        default:
            return false
        }
    }

    func setAccountChangeHandler(_ handler: (@concurrent @Sendable () async -> Void)?) {
        accountChangeObserver.setHandler(handler)
    }

    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) throws -> CloudKitEngineHandle {
        let resources = try ensureResources()
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

    private func ensureResources() throws -> Resources {
        try lock.withLock {
            if let resources { return resources }
            let container = try containerProvider.defaultContainer(for: containerIdentifier)
            guard container.containerIdentifier == containerIdentifier else {
                throw CloudSyncBoundaryError.missingContainerEntitlement(containerIdentifier)
            }
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

private enum CloudSyncInboundWorkError: Error {
    case invalidArchivedRecord
    case accountInvalidated
}

public struct CloudSyncRemoteApplyContext: @unchecked Sendable {
    private let isCurrent: @Sendable () -> Bool

    fileprivate init(isCurrent: @escaping @Sendable () -> Bool) {
        self.isCurrent = isCurrent
    }

    static let unconditional = CloudSyncRemoteApplyContext(isCurrent: { true })

    func ensureCurrent() throws {
        guard isCurrent() else { throw CloudSyncInboundWorkError.accountInvalidated }
    }
}

private final class CloudSyncInboundWorkStore: @unchecked Sendable {
    private struct Batch: Codable {
        let id: UUID
        let records: [Data]
        let deletions: [Deletion]
    }

    private struct Deletion: Codable {
        let recordName: String
        let zoneName: String
        let ownerName: String
        let recordType: String
    }

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let beforePersist: @Sendable () throws -> Void
    private var accountEpoch: UInt = 0

    init(
        defaults: UserDefaults,
        key: String,
        beforePersist: @escaping @Sendable () throws -> Void = {}
    ) {
        self.defaults = defaults
        self.key = key
        self.beforePersist = beforePersist
    }

    func currentAccountEpoch() -> UInt {
        lock.withLock { accountEpoch }
    }

    func enqueue(
        records: [CKRecord],
        deletions: [CloudSyncRemoteDeletion],
        forAccountEpoch accountEpoch: UInt
    ) throws -> (id: UUID, context: CloudSyncRemoteApplyContext)? {
        let batch = Batch(
            id: UUID(),
            records: try records.map(Self.archive),
            deletions: deletions.map {
                Deletion(
                    recordName: $0.recordID.recordName,
                    zoneName: $0.recordID.zoneID.zoneName,
                    ownerName: $0.recordID.zoneID.ownerName,
                    recordType: $0.recordType
                )
            }
        )
        return try lock.withLock { () throws -> (id: UUID, context: CloudSyncRemoteApplyContext)? in
            guard self.accountEpoch == accountEpoch else { return nil }
            try beforePersist()
            var batches = try persistedBatches()
            batches.append(batch)
            try save(batches)
            return (batch.id, remoteApplyContext(for: accountEpoch))
        }
    }

    func replay(
        using handler: @escaping CKSyncEngineBoundary.RemoteChangeHandler
    ) async throws {
        let accountEpoch = currentAccountEpoch()
        let context = remoteApplyContext(for: accountEpoch)
        let batches = try lock.withLock { try persistedBatches() }
        for batch in batches {
            try context.ensureCurrent()
            try await handler(
                batch.records.map { try Self.unarchive($0) },
                batch.deletions.map {
                    CloudSyncRemoteDeletion(
                        recordID: CKRecord.ID(
                            recordName: $0.recordName,
                            zoneID: CKRecordZone.ID(
                                zoneName: $0.zoneName,
                                ownerName: $0.ownerName
                            )
                        ),
                        recordType: $0.recordType
                    )
                },
                context
            )
            try context.ensureCurrent()
            try remove(batch.id)
        }
    }

    func remove(_ id: UUID) throws {
        try lock.withLock {
            var batches = try persistedBatches()
            batches.removeAll { $0.id == id }
            try save(batches)
        }
    }

    func invalidateAccount() {
        lock.withLock {
            accountEpoch &+= 1
            defaults.removeObject(forKey: key)
        }
    }

    private func remoteApplyContext(for accountEpoch: UInt) -> CloudSyncRemoteApplyContext {
        CloudSyncRemoteApplyContext { [weak self] in
            self?.lock.withLock { self?.accountEpoch == accountEpoch } ?? false
        }
    }

    private func persistedBatches() throws -> [Batch] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try decoder.decode([Batch].self, from: data)
    }

    private func save(_ batches: [Batch]) throws {
        guard !batches.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try encoder.encode(batches), forKey: key)
    }

    private static func archive(_ record: CKRecord) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }

    private static func unarchive(_ data: Data) throws -> CKRecord {
        guard let record = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data) else {
            throw CloudSyncInboundWorkError.invalidArchivedRecord
        }
        return record
    }
}

enum PingScopeCKSyncAccountChangePolicy {
    enum Disposition: Equatable {
        case continueSync
        case stopSync
    }

    static func disposition(
        for changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) -> Disposition {
        switch changeType {
        case .signIn:
            .continueSync
        case .signOut, .switchAccounts:
            .stopSync
        @unknown default:
            .stopSync
        }
    }
}

/// The live CloudKit edge. CloudKit resources are created lazily, only after
/// the coordinator has passed the opt-in gate and checks account availability.
public actor CKSyncEngineBoundary: CloudSyncEngineBoundary {
    public typealias RemoteChangeHandler = @Sendable (
        [CKRecord],
        [CloudSyncRemoteDeletion],
        CloudSyncRemoteApplyContext
    ) async throws -> Void
    typealias RemoteChangeAdmissionHook = @Sendable () async -> Void
    typealias SyncEngineCancellation = @Sendable (CKSyncEngine) async -> Void

    private let stateKey: String
    private let subscriptionID: CKSubscription.ID
    private let engineHost: any CloudKitEngineHosting
    private let onRemoteChanges: RemoteChangeHandler
    private let beforeRemoteChangeAdmission: RemoteChangeAdmissionHook
    private let beforeInboundWorkPersist: @Sendable () throws -> Void
    private let inboundWork: CloudSyncInboundWorkStore
    private let defaults: UserDefaults
    private let cancelSyncEngine: SyncEngineCancellation
    private var resourcesInitialized = false
    private var delegate: PingScopeCKSyncEngineDelegate?
    private var engineHandle: CloudKitEngineHandle?
    private var accountChangeHandler: (@concurrent @Sendable () async -> Void)?
    private var isHandlingAccountChange = false
    private var hasPendingAccountChange = false

    public init(
        containerIdentifier: String = PingScopeCloudKitModel.containerIdentifier,
        stateKey: String = "PingScope.CloudSync.CKSyncEngineState",
        subscriptionID: CKSubscription.ID = "PingScope.CloudSync.PrivateDatabase",
        defaultsSuiteName: String? = nil,
        onRemoteChanges: @escaping RemoteChangeHandler = { _, _, _ in }
    ) {
        self.stateKey = stateKey
        self.subscriptionID = subscriptionID
        self.engineHost = LiveCloudKitEngineHost(containerIdentifier: containerIdentifier)
        self.onRemoteChanges = onRemoteChanges
        self.beforeRemoteChangeAdmission = {}
        self.beforeInboundWorkPersist = {}
        let defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        self.inboundWork = CloudSyncInboundWorkStore(
            defaults: defaults,
            key: "\(stateKey).InboundWork",
            beforePersist: beforeInboundWorkPersist
        )
        self.cancelSyncEngine = { await $0.cancelOperations() }
    }

    init(
        engineHost: any CloudKitEngineHosting,
        stateKey: String,
        subscriptionID: CKSubscription.ID,
        defaultsSuiteName: String? = nil,
        onRemoteChanges: @escaping RemoteChangeHandler = { _, _, _ in },
        beforeRemoteChangeAdmission: @escaping RemoteChangeAdmissionHook = {},
        beforeInboundWorkPersist: @escaping @Sendable () throws -> Void = {},
        cancelSyncEngine: @escaping SyncEngineCancellation = { await $0.cancelOperations() }
    ) {
        self.stateKey = stateKey
        self.subscriptionID = subscriptionID
        self.engineHost = engineHost
        self.onRemoteChanges = onRemoteChanges
        self.beforeRemoteChangeAdmission = beforeRemoteChangeAdmission
        self.beforeInboundWorkPersist = beforeInboundWorkPersist
        let defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        self.inboundWork = CloudSyncInboundWorkStore(
            defaults: defaults,
            key: "\(stateKey).InboundWork",
            beforePersist: beforeInboundWorkPersist
        )
        self.cancelSyncEngine = cancelSyncEngine
    }

    public func accountAvailability() async throws -> CloudSyncAccountAvailability {
        let availability = try await engineHost.accountAvailability()
        resourcesInitialized = true
        return availability
    }

    public func setAccountChangeHandler(_ handler: (@concurrent @Sendable () async -> Void)?) async {
        accountChangeHandler = handler
        // Keep observing after opt-out so an account switch cannot leave the
        // previous account's serialized CKSyncEngine state on disk.
        engineHost.setAccountChangeHandler { [weak self] in
            await self?.accountDidChange()
        }
    }

    public func start() async throws {
        guard engineHandle == nil else { return }
        try engineHost.prepareResources()
        resourcesInitialized = true
        let delegate = ensureDelegate()
        await delegate.setActive(true)
        let engineHandle = try engineHost.createEngine(
            stateSerialization: delegate.restoredStateSerialization(),
            delegate: delegate,
            subscriptionID: subscriptionID
        )
        self.engineHandle = engineHandle

        engineHost.addPendingDatabaseChanges([
            .saveZone(CKRecordZone(zoneID: PingScopeCloudKitModel.zoneID))
        ], to: engineHandle)
        do {
            DebugLog.write("CloudKit engine startup sending pending changes")
            try await engineHost.sendChanges(on: engineHandle)
            DebugLog.write("CloudKit engine startup finished sending pending changes")
            guard self.engineHandle == engineHandle, await delegate.isActive() else {
                await engineHost.cancelOperations(on: engineHandle)
                return
            }
            try await inboundWork.replay(using: onRemoteChanges)
            guard self.engineHandle == engineHandle, await delegate.isActive() else {
                await engineHost.cancelOperations(on: engineHandle)
                return
            }
            DebugLog.write("CloudKit engine startup fetching changes")
            try await engineHost.fetchChanges(on: engineHandle)
            DebugLog.write("CloudKit engine startup finished fetching changes")
        } catch {
            DebugLog.write("CloudKit engine startup failed: \(error)")
            await engineHost.cancelOperations(on: engineHandle)
            engineHost.releaseEngine(engineHandle)
            self.engineHandle = nil
            await delegate.setActive(false)
            throw error
        }
    }

    public func stop() async {
        guard resourcesInitialized else { return }
        let completedDeferredCancellation: Bool
        if let delegate {
            completedDeferredCancellation = await delegate.awaitDeferredCancellation()
        } else {
            completedDeferredCancellation = false
        }
        if let engineHandle, !completedDeferredCancellation {
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
        self.delegate = nil
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

    public func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        guard let engineHandle, let delegate,
              await delegate.prepare(records: records, deletions: deletions),
              self.engineHandle == engineHandle,
              self.delegate === delegate else {
            throw CloudSyncBoundaryError.inactive
        }
        guard await delegate.stage(records: records),
              self.engineHandle == engineHandle,
              self.delegate === delegate else {
            throw CloudSyncBoundaryError.inactive
        }
        engineHost.addPendingRecordZoneChanges(
            records.map { .saveRecord($0.recordID) }
                + deletions.map(CKSyncEngine.PendingRecordZoneChange.deleteRecord),
            to: engineHandle
        )
        try await engineHost.sendChanges(on: engineHandle)
        if let failure = await delegate.deleteFailure(for: deletions) {
            throw failure
        }
        return await delegate.consumeSaveConfirmation(for: records.map(\.recordID))
    }

    private func ensureDelegate() -> PingScopeCKSyncEngineDelegate {
        if let delegate { return delegate }
        let delegate = PingScopeCKSyncEngineDelegate(
            stateKey: stateKey,
            defaults: defaults,
            onRemoteChanges: onRemoteChanges,
            inboundWork: inboundWork,
            beforeRemoteChangeAdmission: beforeRemoteChangeAdmission,
            onInboundWorkFailure: { [weak self] in
                await self?.handleInboundWorkFailure()
            },
            onAccountChange: { [weak self] in
                Task.detached { await self?.accountDidChange() }
            },
            cancelSyncEngine: cancelSyncEngine
        )
        self.delegate = delegate
        return delegate
    }

    private func accountDidChange() async {
        hasPendingAccountChange = true
        guard !isHandlingAccountChange else { return }
        isHandlingAccountChange = true
        defer { isHandlingAccountChange = false }
        while hasPendingAccountChange {
            hasPendingAccountChange = false
            await delegate?.setActive(false)
            defaults.removeObject(forKey: stateKey)
            inboundWork.invalidateAccount()
            await accountChangeHandler?()
        }
    }

    private func handleInboundWorkFailure() async {
        guard let engineHandle else { return }
        await delegate?.setActive(false)
        await engineHost.cancelOperations(on: engineHandle)
        engineHost.releaseEngine(engineHandle)
        self.engineHandle = nil
        delegate = nil
        await accountChangeHandler?()
    }
}

actor PingScopeCKSyncEngineDelegateState {
    private var active = false
    private var acceptsDeferredCancellation = true
    private var deferredCancellation: Task<Void, Never>?
    private var stagedRecords: [CKRecord.ID: CKRecord] = [:]
    private var awaitingRecordSaveIDs: Set<CKRecord.ID> = []
    private var confirmedRecordSaveIDs: Set<CKRecord.ID> = []
    private var failedRecordSaves: [CKRecord.ID: CKError] = [:]
    private var failedDeletions: [CKRecord.ID: CKError] = [:]

    func setActive(_ value: Bool) {
        active = value
        if value {
            acceptsDeferredCancellation = true
        }
    }

    func scheduleCancellation(operation: @escaping @Sendable () async -> Void) {
        active = false
        guard acceptsDeferredCancellation else { return }
        let previousCancellation = deferredCancellation
        deferredCancellation = Task.detached {
            await previousCancellation?.value
            await operation()
        }
    }

    func deactivateAndAwaitDeferredCancellation() async -> Bool {
        active = false
        acceptsDeferredCancellation = false
        let completedDeferredCancellation = deferredCancellation != nil
        await deferredCancellation?.value
        deferredCancellation = nil
        stagedRecords.removeAll(keepingCapacity: false)
        awaitingRecordSaveIDs.removeAll(keepingCapacity: false)
        confirmedRecordSaveIDs.removeAll(keepingCapacity: false)
        failedRecordSaves.removeAll(keepingCapacity: false)
        failedDeletions.removeAll(keepingCapacity: false)
        return completedDeferredCancellation
    }

    @discardableResult
    func stage(_ records: [CKRecord]) -> Bool {
        guard active else { return false }
        for record in records { stagedRecords[record.recordID] = record }
        return true
    }

    func record(for id: CKRecord.ID) -> CKRecord? {
        guard active else { return nil }
        return stagedRecords[id]
    }

    func remove(_ ids: [CKRecord.ID]) {
        for id in ids { stagedRecords[id] = nil }
    }

    @discardableResult
    func prepare(records: [CKRecord], deletions: [CKRecord.ID]) -> Bool {
        guard active else { return false }
        for id in records.map(\.recordID) {
            awaitingRecordSaveIDs.insert(id)
            confirmedRecordSaveIDs.remove(id)
            failedRecordSaves[id] = nil
        }
        for id in deletions { failedDeletions[id] = nil }
        return true
    }

    func recordSaveResults(savedRecordIDs: [CKRecord.ID], failures: [CKRecord.ID: CKError]) {
        guard active else { return }
        for id in savedRecordIDs where awaitingRecordSaveIDs.contains(id) {
            confirmedRecordSaveIDs.insert(id)
            failedRecordSaves[id] = nil
        }
        for (id, error) in failures where awaitingRecordSaveIDs.contains(id) {
            confirmedRecordSaveIDs.remove(id)
            failedRecordSaves[id] = error
        }
    }

    func consumeSaveConfirmation(for ids: [CKRecord.ID]) -> CloudSyncUploadConfirmation {
        let requestedIDs = Set(ids)
        let confirmedIDs = confirmedRecordSaveIDs.intersection(requestedIDs)
        let failures = Dictionary(uniqueKeysWithValues: requestedIDs.compactMap { id in
            failedRecordSaves[id].map { (id, $0) }
        })
        awaitingRecordSaveIDs.subtract(requestedIDs)
        confirmedRecordSaveIDs.subtract(requestedIDs)
        for id in requestedIDs {
            stagedRecords[id] = nil
            failedRecordSaves[id] = nil
        }
        return CloudSyncUploadConfirmation(
            requestedRecordIDs: requestedIDs,
            confirmedRecordIDs: confirmedIDs,
            failedRecordSaveErrors: failures
        )
    }

    func recordDeleteFailures(_ failures: [CKRecord.ID: CKError]) {
        guard active else { return }
        for (id, error) in failures { failedDeletions[id] = error }
    }

    func deleteFailure(for ids: [CKRecord.ID]) -> CKError? {
        ids.lazy.compactMap { self.failedDeletions[$0] }.first
    }

    func isActive() -> Bool { active }

    func cacheCounts() -> (
        stagedRecords: Int,
        awaitingRecordSaves: Int,
        confirmedRecordSaves: Int,
        failedRecordSaves: Int,
        failedDeletions: Int
    ) {
        (
            stagedRecords.count,
            awaitingRecordSaveIDs.count,
            confirmedRecordSaveIDs.count,
            failedRecordSaves.count,
            failedDeletions.count
        )
    }
}

final class PingScopeCKSyncEngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private let state = PingScopeCKSyncEngineDelegateState()
    private let stateKey: String
    private let defaults: UserDefaults
    private let onRemoteChanges: CKSyncEngineBoundary.RemoteChangeHandler
    private let inboundWork: CloudSyncInboundWorkStore
    private let beforeRemoteChangeAdmission: CKSyncEngineBoundary.RemoteChangeAdmissionHook
    private let onInboundWorkFailure: @Sendable () async -> Void
    private let onAccountChange: @Sendable () -> Void
    private let cancelSyncEngine: CKSyncEngineBoundary.SyncEngineCancellation

    fileprivate init(
        stateKey: String,
        defaults: UserDefaults,
        onRemoteChanges: @escaping CKSyncEngineBoundary.RemoteChangeHandler,
        inboundWork: CloudSyncInboundWorkStore,
        beforeRemoteChangeAdmission: @escaping CKSyncEngineBoundary.RemoteChangeAdmissionHook,
        onInboundWorkFailure: @escaping @Sendable () async -> Void,
        onAccountChange: @escaping @Sendable () -> Void,
        cancelSyncEngine: @escaping CKSyncEngineBoundary.SyncEngineCancellation = {
            await $0.cancelOperations()
        }
    ) {
        self.stateKey = stateKey
        self.defaults = defaults
        self.onRemoteChanges = onRemoteChanges
        self.inboundWork = inboundWork
        self.beforeRemoteChangeAdmission = beforeRemoteChangeAdmission
        self.onInboundWorkFailure = onInboundWorkFailure
        self.onAccountChange = onAccountChange
        self.cancelSyncEngine = cancelSyncEngine
    }

    func restoredStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func setActive(_ active: Bool) async { await state.setActive(active) }
    func awaitDeferredCancellation() async -> Bool {
        await state.deactivateAndAwaitDeferredCancellation()
    }
    func isActive() async -> Bool { await state.isActive() }
    func stage(records: [CKRecord]) async -> Bool { await state.stage(records) }
    func prepare(records: [CKRecord], deletions: [CKRecord.ID]) async -> Bool {
        await state.prepare(records: records, deletions: deletions)
    }
    func consumeSaveConfirmation(for ids: [CKRecord.ID]) async -> CloudSyncUploadConfirmation {
        await state.consumeSaveConfirmation(for: ids)
    }
    func recordSaveResultsForTesting(
        savedRecordIDs: [CKRecord.ID],
        failures: [CKRecord.ID: CKError]
    ) async {
        await state.recordSaveResults(savedRecordIDs: savedRecordIDs, failures: failures)
        await state.remove(savedRecordIDs)
    }
    func deleteFailure(for ids: [CKRecord.ID]) async -> CKError? { await state.deleteFailure(for: ids) }

    func handleFetchedRecordZoneChanges(
        records: [CKRecord],
        deletions: [CloudSyncRemoteDeletion]
    ) async {
        guard await state.isActive() else { return }
        let accountEpoch = inboundWork.currentAccountEpoch()
        await beforeRemoteChangeAdmission()
        guard await state.isActive() else { return }
        do {
            guard let admission = try inboundWork.enqueue(
                records: records,
                deletions: deletions,
                forAccountEpoch: accountEpoch
            ) else {
                return
            }
            do {
                try await onRemoteChanges(records, deletions, admission.context)
                try inboundWork.remove(admission.id)
            } catch {
                DebugLog.write("CloudKit inbound changes will replay after restart: \(error)")
            }
        } catch {
            DebugLog.write("CloudKit inbound changes could not be persisted: \(error)")
            await onInboundWorkFailure()
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        if case let .accountChange(change) = event {
            switch PingScopeCKSyncAccountChangePolicy.disposition(for: change.changeType) {
            case .continueSync:
                // CKSyncEngine reports the current signed-in account while a
                // newly created, active engine starts. That is confirmation of
                // the engine we just created, not a transition requiring a
                // teardown/restart. An inactive retained delegate still uses
                // sign-in to ask the coordinator to build a fresh engine.
                guard !(await state.isActive()) else { return }
                await state.setActive(false)
            case .stopSync:
                // CKSyncEngine traps if this callback directly awaits an
                // operation that can reenter the delegate. The state actor owns
                // the deferred task so boundary shutdown can await its lifetime.
                await state.scheduleCancellation(operation: { [cancelSyncEngine] in
                    await cancelSyncEngine(syncEngine)
                })
            }
            onAccountChange()
            return
        }
        guard await state.isActive() else { return }
        switch event {
        case let .stateUpdate(update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                defaults.set(data, forKey: stateKey)
            }
        case let .fetchedRecordZoneChanges(changes):
            let records = changes.modifications.map(\.record)
            let deletions = changes.deletions.map {
                CloudSyncRemoteDeletion(recordID: $0.recordID, recordType: $0.recordType)
            }
            await handleFetchedRecordZoneChanges(records: records, deletions: deletions)
        case let .sentRecordZoneChanges(changes):
            await state.recordSaveResults(
                savedRecordIDs: changes.savedRecords.map(\.recordID),
                failures: Dictionary(uniqueKeysWithValues: changes.failedRecordSaves.map {
                    ($0.record.recordID, $0.error)
                })
            )
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
