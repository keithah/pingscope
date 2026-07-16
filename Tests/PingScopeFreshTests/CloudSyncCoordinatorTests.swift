import CloudKit
import XCTest
import PingScopeCore
@testable import PingScopeCloudSync

// SwiftPM tests cover CKSyncEngineBoundary orchestration through an injected
// CloudKitEngineHosting edge. The production adapter's entitled CKContainer,
// live send/fetch, and subscription deletion require an on-device/Xcode smoke.

final class CloudSyncCoordinatorTests: XCTestCase {
    func testCloudSyncPreferenceDefaultsOff() {
        let suiteName = "CloudSyncPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(PingScopeCloudSyncPreference.isEnabled(in: defaults))
    }

    func testToggleOffNeverStartsEngineOrCreatesOrUploadsRecordsAndStopsFurtherActivity() async throws {
        let boundary = FakeCloudSyncBoundary(availability: .privateAccount)
        let builder = CountingCloudSyncRecordBuilder()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary, recordBuilder: builder)
        let host = HostConfig(displayName: "HTTPS", address: "example.com", method: .https, port: 443)
        let sample = PingResult.success(hostID: host.id, latency: .milliseconds(20))

        await coordinator.setEnabled(false)
        _ = try await coordinator.upload(samples: [sample], hosts: [CloudSyncHostVersion(config: host, modifiedAt: .now)])

        var stats = await boundary.stats()
        var recordCount = await builder.count()
        XCTAssertEqual(stats.startCount, 0)
        XCTAssertEqual(recordCount, 0)
        XCTAssertEqual(stats.uploadedRecordCount, 0)

        await coordinator.setEnabled(true)
        _ = try await coordinator.upload(samples: [sample], hosts: [CloudSyncHostVersion(config: host, modifiedAt: .now)])
        stats = await boundary.stats()
        recordCount = await builder.count()
        XCTAssertEqual(stats.startCount, 1)
        XCTAssertEqual(recordCount, 2)
        XCTAssertEqual(stats.uploadedRecordCount, 2)

        await coordinator.setEnabled(false)
        _ = try await coordinator.upload(samples: [sample], hosts: [CloudSyncHostVersion(config: host, modifiedAt: .now)])
        stats = await boundary.stats()
        recordCount = await builder.count()
        XCTAssertEqual(stats.stopCount, 2)
        XCTAssertEqual(recordCount, 2)
        XCTAssertEqual(stats.uploadedRecordCount, 2)
    }

    func testDisablingTearsDownSubscriptionExactlyOnceBeforeStoppingWithoutUploading() async {
        let boundary = FakeCloudSyncBoundary(availability: .privateAccount)
        let builder = CountingCloudSyncRecordBuilder()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary, recordBuilder: builder)

        await coordinator.setEnabled(true)
        await coordinator.setEnabled(false)

        let stats = await boundary.stats()
        let recordCount = await builder.count()
        let status = await coordinator.status
        XCTAssertEqual(stats.subscriptionTeardownCount, 1)
        XCTAssertEqual(stats.stopCount, 1)
        XCTAssertEqual(stats.lifecycleEvents, [.tearDownSubscription, .stop])
        XCTAssertEqual(stats.uploadedRecordCount, 0)
        XCTAssertEqual(recordCount, 0)
        XCTAssertEqual(status, .off)
    }

    func testSubscriptionTeardownFailureStillStopsAndLeavesSyncDisabled() async {
        let boundary = FakeCloudSyncBoundary(
            availability: .privateAccount,
            subscriptionTeardownError: FakeCloudSyncBoundaryError.teardownFailed
        )
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)

        await coordinator.setEnabled(true)
        await coordinator.setEnabled(false)

        let stats = await boundary.stats()
        let status = await coordinator.status
        XCTAssertEqual(stats.subscriptionTeardownCount, 1)
        XCTAssertEqual(stats.stopCount, 1)
        XCTAssertEqual(stats.lifecycleEvents, [.tearDownSubscription, .stop])
        XCTAssertEqual(stats.uploadedRecordCount, 0)
        XCTAssertEqual(status, .off)
    }

    func testRepeatedDisableCallsStopWithoutStartingOrUploading() async {
        let boundary = FakeCloudSyncBoundary(availability: .privateAccount)
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)

        await coordinator.setEnabled(false)
        await coordinator.setEnabled(false)

        let stats = await boundary.stats()
        let status = await coordinator.status
        XCTAssertEqual(stats.stopCount, 2)
        XCTAssertEqual(stats.startCount, 0)
        XCTAssertEqual(stats.uploadedRecordCount, 0)
        XCTAssertEqual(status, .off)
    }

    func testRealBoundaryNeverEnabledStopDoesNotConstructCloudKitResourcesOrTouchHost() async throws {
        // This default production boundary would SIGTRAP under SwiftPM if stop
        // or teardown accidentally constructed its CKContainer.
        let productionBoundary = CKSyncEngineBoundary(
            stateKey: "CloudSyncBoundaryTests-\(UUID().uuidString)"
        )
        await productionBoundary.stop()
        try await productionBoundary.tearDownSubscriptions()

        let fixture = makeRealBoundaryFixture()

        await fixture.boundary.stop()
        try await fixture.boundary.tearDownSubscriptions()

        let events = await fixture.host.events()
        XCTAssertEqual(events, [])
    }

    func testRealBoundaryStartedStopDeletesStableSubscriptionOnceReleasesEngineAndBecomesInactive() async throws {
        let fixture = makeRealBoundaryFixture()

        try await fixture.boundary.start()
        await fixture.boundary.stop()

        let events = await fixture.host.events()
        XCTAssertEqual(events, [
            .prepareResources,
            .createEngine(subscriptionID: fixture.subscriptionID),
            .addDatabaseChanges,
            .sendChanges,
            .fetchChanges,
            .cancel,
            .deleteSubscription(fixture.subscriptionID),
            .release
        ])
        await assertBoundaryIsInactive(fixture.boundary)
    }

    func testRealBoundaryUnknownSubscriptionIsIdempotentSuccessAndReleasesEngine() async throws {
        let fixture = makeRealBoundaryFixture(deleteError: CKError(.unknownItem))

        try await fixture.boundary.start()
        await fixture.boundary.stop()

        let deletedIDs = await fixture.host.deletedSubscriptionIDs()
        XCTAssertEqual(deletedIDs, [fixture.subscriptionID])
        let events = await fixture.host.events()
        XCTAssertEqual(events.filter { $0 == .release }.count, 1)
        await assertBoundaryIsInactive(fixture.boundary)
    }

    func testRealBoundarySubscriptionDeleteFailureIsContainedAndReleasesEngine() async throws {
        let fixture = makeRealBoundaryFixture(deleteError: CKError(.networkFailure))

        try await fixture.boundary.start()
        await fixture.boundary.stop()

        let deletedIDs = await fixture.host.deletedSubscriptionIDs()
        XCTAssertEqual(deletedIDs, [fixture.subscriptionID])
        let events = await fixture.host.events()
        XCTAssertEqual(events.filter { $0 == .release }.count, 1)
        await assertBoundaryIsInactive(fixture.boundary)
    }

    func testUnavailableOrNonPrivateAccountBailsOutWithoutSyncOrRecordCreation() async throws {
        for availability in [CloudSyncAccountAvailability.unavailable, .notPrivateAccount] {
            let boundary = FakeCloudSyncBoundary(availability: availability)
            let builder = CountingCloudSyncRecordBuilder()
            let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary, recordBuilder: builder)
            await coordinator.setEnabled(true)
            _ = try await coordinator.upload(samples: [.failure(hostID: UUID(), reason: .timeout)], hosts: [])
            let stats = await boundary.stats()
            let recordCount = await builder.count()
            let status = await coordinator.status
            XCTAssertEqual(stats.startCount, 0)
            XCTAssertEqual(recordCount, 0)
            XCTAssertEqual(stats.uploadedRecordCount, 0)
            XCTAssertEqual(status, .accountUnavailable)
        }
    }

    func testDisablingDuringStartupStopsBoundaryAndPreventsLateUpload() async throws {
        let boundary = SuspendingCloudSyncBoundary()
        let builder = CountingCloudSyncRecordBuilder()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary, recordBuilder: builder)

        let enabling = Task { await coordinator.setEnabled(true) }
        try await Task.sleep(for: .milliseconds(10))
        await coordinator.setEnabled(false)
        await enabling.value
        _ = try await coordinator.upload(
            samples: [.success(hostID: UUID(), latency: .milliseconds(1))],
            hosts: []
        )

        let stopCount = await boundary.stopCount()
        let uploadCount = await boundary.uploadCount()
        let recordCount = await builder.count()
        XCTAssertGreaterThanOrEqual(stopCount, 1)
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(recordCount, 0)
    }

    func testApplyingRemoteSampleRecordsIsIdempotentAndDeletionPropagates() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncCoordinatorTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SQLiteHistoryStore(url: url)
        let sample = PingResult.success(
            hostID: UUID(),
            latency: .milliseconds(15),
            timestamp: Date(timeIntervalSince1970: 500),
            location: SampleLocation(latitude: 37.3, longitude: -122.0),
            networkInterface: "wifi",
            networkName: "Home",
            isVPN: true
        )
        let record = PingSampleRecordMapper.record(from: sample)

        try await CloudSyncRemoteChangeApplier.apply(sampleRecords: [record], to: store)
        try await CloudSyncRemoteChangeApplier.apply(sampleRecords: [record], to: store)
        var stored = await store.samples(hostID: sample.hostID, since: .distantPast, limit: 10)
        XCTAssertEqual(stored, [sample])

        try await CloudSyncRemoteChangeApplier.deleteSampleRecordIDs([record.recordID], from: store)
        stored = await store.samples(hostID: sample.hostID, since: .distantPast, limit: 10)
        XCTAssertEqual(stored, [])
    }

    func testSQLiteSyncCursorTracksLocalRowsAndTreatsRemoteRowsAsAlreadySynced() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncCursorTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SQLiteHistoryStore(url: url)
        let local = PingResult.success(
            hostID: UUID(),
            latency: .milliseconds(10),
            timestamp: Date(timeIntervalSince1970: 123_456)
        )
        let remote = PingResult.failure(hostID: UUID(), reason: .timeout)

        try await store.appendAndWait([local])
        try await store.upsertRemoteSamples([remote])
        var unsynced = try await store.unsyncedSamples(limit: 300)
        XCTAssertEqual(unsynced.map(\.id), [local.id])
        XCTAssertEqual(try XCTUnwrap(unsynced.first?.latency).milliseconds, 10, accuracy: 0.01)

        try await store.markSamplesSynced(ids: [local.id])
        unsynced = try await store.unsyncedSamples(limit: 300)
        XCTAssertEqual(unsynced, [])
    }

    func testHostConflictPolicyUsesNewestModifiedDateAndLocalWinsTies() {
        let id = UUID()
        let local = CloudSyncHostVersion(
            config: HostConfig(id: id, displayName: "Local", address: "local.example"),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let olderRemote = CloudSyncHostVersion(
            config: HostConfig(id: id, displayName: "Older", address: "old.example"),
            modifiedAt: Date(timeIntervalSince1970: 99)
        )
        let newerRemote = CloudSyncHostVersion(
            config: HostConfig(id: id, displayName: "Newer", address: "new.example"),
            modifiedAt: Date(timeIntervalSince1970: 101)
        )
        let tiedRemote = CloudSyncHostVersion(
            config: HostConfig(id: id, displayName: "Tie", address: "tie.example"),
            modifiedAt: local.modifiedAt
        )

        XCTAssertEqual(CloudSyncConflictResolver.resolve(local: local, remote: olderRemote), local)
        XCTAssertEqual(CloudSyncConflictResolver.resolve(local: local, remote: newerRemote), newerRemote)
        XCTAssertEqual(CloudSyncConflictResolver.resolve(local: local, remote: tiedRemote), local)
    }

    func testConcurrentUnrelatedHostEditDoesNotOverwriteNewerPeerHostVersion() async throws {
        let hostID = UUID()
        let otherID = UUID()
        let originalHost = HostConfig(id: hostID, displayName: "Host", address: "old.example")
        let originalOther = HostConfig(id: otherID, displayName: "Other", address: "other.example")
        let hostEditedOnA = HostConfig(id: hostID, displayName: "Host A", address: "a.example")
        let otherEditedOnB = HostConfig(id: otherID, displayName: "Other B", address: "b.example")
        let baseline = Date().addingTimeInterval(1_000)

        let deviceA = makeServiceFixture(hosts: [originalHost, originalOther])
        let deviceB = makeServiceFixture(hosts: [originalHost, originalOther])
        defer {
            deviceA.cleanup()
            deviceB.cleanup()
        }
        await deviceA.service.setEnabled(true, hosts: [originalHost, originalOther])
        await deviceB.service.setEnabled(true, hosts: [originalHost, originalOther])
        await deviceA.boundary.resetUploads()
        await deviceB.boundary.resetUploads()

        try deviceA.hostStore.save(SharedHostStoreState(hosts: [hostEditedOnA, originalOther]))
        await deviceA.service.uploadHosts(
            [hostEditedOnA, originalOther],
            modifiedAt: baseline.addingTimeInterval(10)
        )
        try deviceB.hostStore.save(SharedHostStoreState(hosts: [originalHost, otherEditedOnB]))
        await deviceB.service.uploadHosts(
            [originalHost, otherEditedOnB],
            modifiedAt: baseline.addingTimeInterval(20)
        )

        let uploadsFromA = await deviceA.boundary.uploadedHostVersions()
        let uploadsFromB = await deviceB.boundary.uploadedHostVersions()
        XCTAssertEqual(uploadsFromA.map(\.config.id), [hostID])
        XCTAssertEqual(uploadsFromB.map(\.config.id), [otherID])

        let hostRecordFromA = try MonitoredHostRecordMapper.record(
            from: hostEditedOnA,
            modifiedAt: baseline.addingTimeInterval(10)
        )
        let otherRecordFromB = try MonitoredHostRecordMapper.record(
            from: otherEditedOnB,
            modifiedAt: baseline.addingTimeInterval(20)
        )
        await deviceA.service.applyRemoteChanges(records: [otherRecordFromB])
        await deviceB.service.applyRemoteChanges(records: [hostRecordFromA])

        let convergedA = try XCTUnwrap(deviceA.hostStore.load().state?.hosts)
        let convergedB = try XCTUnwrap(deviceB.hostStore.load().state?.hosts)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: convergedA.map { ($0.id, $0) }), [
            hostID: hostEditedOnA,
            otherID: otherEditedOnB
        ])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: convergedB.map { ($0.id, $0) }), [
            hostID: hostEditedOnA,
            otherID: otherEditedOnB
        ])
    }

    func testEditingOneHostUploadsExactlyOneHostAndDoesNotBumpUnchangedHost() async throws {
        let host = HostConfig(displayName: "Host", address: "old.example")
        let unchanged = HostConfig(displayName: "Unchanged", address: "steady.example")
        let edited = HostConfig(id: host.id, displayName: "Host", address: "new.example")
        let fixture = makeServiceFixture(hosts: [host, unchanged])
        defer { fixture.cleanup() }
        await fixture.service.setEnabled(true, hosts: [host, unchanged])
        await fixture.boundary.resetUploads()

        let editDate = Date().addingTimeInterval(1_000)
        await fixture.service.uploadHosts([edited, unchanged], modifiedAt: editDate)

        let uploaded = await fixture.boundary.uploadedHostVersions()
        XCTAssertEqual(uploaded.count, 1)
        XCTAssertEqual(uploaded.first?.config, edited)
        XCTAssertEqual(uploaded.first?.modifiedAt, editDate)

        await fixture.boundary.resetUploads()
        await fixture.service.uploadHosts([edited, unchanged], modifiedAt: editDate.addingTimeInterval(100))
        let repeatedUploadCount = await fixture.boundary.uploadCallCount()
        XCTAssertEqual(repeatedUploadCount, 0)
    }

    func testApplyingRemoteHostChangeDoesNotEchoUpload() async throws {
        let host = HostConfig(displayName: "Host", address: "old.example")
        let remote = HostConfig(id: host.id, displayName: "Remote", address: "remote.example")
        let fixture = makeServiceFixture(hosts: [host])
        defer { fixture.cleanup() }
        await fixture.service.setEnabled(true, hosts: [host])

        let remoteDate = Date().addingTimeInterval(1_000)
        let remoteRecord = try MonitoredHostRecordMapper.record(from: remote, modifiedAt: remoteDate)
        await fixture.service.applyRemoteChanges(records: [remoteRecord])
        await fixture.boundary.resetUploads()

        let appliedHosts = try XCTUnwrap(fixture.hostStore.load().state?.hosts)
        await fixture.service.uploadHosts(appliedHosts, modifiedAt: remoteDate.addingTimeInterval(100))

        let uploadCount = await fixture.boundary.uploadCallCount()
        XCTAssertEqual(appliedHosts, [remote])
        XCTAssertEqual(uploadCount, 0)
    }

    func testTransientBacklogFailureIsRetriedAfterLaterSuccessfulAppend() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncBacklogRetryTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let historyStore = SQLiteHistoryStore(url: url)
        let host = HostConfig(displayName: "Host", address: "example.com")
        let fixture = makeServiceFixture(
            hosts: [host],
            historyStore: historyStore,
            failingUploadAttempts: [2]
        )
        defer { fixture.cleanup() }
        let backlog = (0..<3).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset + 1)),
                timestamp: Date(timeIntervalSince1970: Double(1_000 + offset))
            )
        }
        try await historyStore.appendAndWait(backlog)

        await fixture.service.setEnabled(true, hosts: [host])
        var unsynced = try await historyStore.unsyncedSamples(limit: 300)
        XCTAssertEqual(Set(unsynced.map(\.id)), Set(backlog.map(\.id)))

        let later = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: Date(timeIntervalSince1970: 2_000)
        )
        try await historyStore.appendAndWait([later])
        let didUploadLater = await fixture.service.uploadSamples([later])
        XCTAssertTrue(didUploadLater)

        unsynced = try await historyStore.unsyncedSamples(limit: 300)
        XCTAssertEqual(unsynced, [])
    }

    func testDeleteWhileOffThenEnableDoesNotResurrectRemoteHost() async throws {
        let host = HostConfig(displayName: "Deleted", address: "deleted.example")
        let fixture = makeServiceFixture(hosts: [host])
        defer { fixture.cleanup() }
        try fixture.hostStore.save(SharedHostStoreState(hosts: []))

        await fixture.service.deleteHost(id: host.id)
        let remoteRecord = try MonitoredHostRecordMapper.record(from: host, modifiedAt: .now)
        await fixture.service.applyRemoteChanges(records: [remoteRecord])
        await fixture.service.setEnabled(true, hosts: [])

        XCTAssertEqual(fixture.hostStore.load().state?.hosts, [])
        let deletedIDs = await fixture.boundary.uploadedDeletionIDs()
        XCTAssertEqual(deletedIDs, [host.id])
    }

    func testFailedHostDeletionPersistsAndRetriesAfterServiceRecreation() async throws {
        let host = HostConfig(displayName: "Deleted", address: "deleted.example")
        let first = makeServiceFixture(hosts: [host], failingUploadAttempts: [2])
        defer { first.cleanup() }
        await first.service.setEnabled(true, hosts: [host])
        try first.hostStore.save(SharedHostStoreState(hosts: []))

        await first.service.deleteHost(id: host.id)
        let failedDeletionIDs = await first.boundary.uploadedDeletionIDs()
        XCTAssertEqual(failedDeletionIDs, [])

        let second = makeServiceFixture(
            hosts: [],
            hostStore: first.hostStore,
            suiteName: first.suiteName
        )
        let staleRemote = try MonitoredHostRecordMapper.record(from: host, modifiedAt: .now)
        await second.service.applyRemoteChanges(records: [staleRemote])
        await second.service.setEnabled(true, hosts: [])

        XCTAssertEqual(first.hostStore.load().state?.hosts, [])
        let retriedDeletionIDs = await second.boundary.uploadedDeletionIDs()
        XCTAssertEqual(retriedDeletionIDs, [host.id])
    }

    func testConfirmedHostDeletionClearsPendingStateAndVersionTracking() async throws {
        let host = HostConfig(displayName: "Deleted", address: "deleted.example")
        let fixture = makeServiceFixture(hosts: [host])
        defer { fixture.cleanup() }
        await fixture.service.setEnabled(true, hosts: [host])
        await fixture.service.setEnabled(false, hosts: [host])
        try fixture.hostStore.save(SharedHostStoreState(hosts: []))

        await fixture.service.deleteHost(id: host.id)
        await fixture.boundary.resetUploads()
        await fixture.service.setEnabled(true, hosts: [])
        let confirmedDeletionIDs = await fixture.boundary.uploadedDeletionIDs()
        XCTAssertEqual(confirmedDeletionIDs, [host.id])

        await fixture.boundary.resetUploads()
        await fixture.service.setEnabled(false, hosts: [])
        await fixture.service.setEnabled(true, hosts: [])
        let repeatedDeletionIDs = await fixture.boundary.uploadedDeletionIDs()
        XCTAssertEqual(repeatedDeletionIDs, [])

        try fixture.hostStore.save(SharedHostStoreState(hosts: [host]))
        await fixture.service.uploadHosts([host], modifiedAt: Date().addingTimeInterval(1_000))
        let readdedHosts = await fixture.boundary.uploadedHostVersions().map(\.config)
        XCTAssertEqual(readdedHosts, [host])
    }

    func testAlreadyDeletedRemoteHostClearsPendingDeletionWithoutLooping() async throws {
        let host = HostConfig(displayName: "Already Gone", address: "gone.example")
        let fixture = makeServiceFixture(hosts: [], unknownItemUploadAttempts: [1])
        defer { fixture.cleanup() }

        await fixture.service.deleteHost(id: host.id)
        await fixture.service.setEnabled(true, hosts: [])
        let initialDeletionIDs = await fixture.boundary.attemptedDeletionIDs()
        XCTAssertEqual(initialDeletionIDs, [host.id])

        await fixture.boundary.resetUploads()
        await fixture.service.setEnabled(false, hosts: [])
        await fixture.service.setEnabled(true, hosts: [])
        let repeatedDeletionIDs = await fixture.boundary.attemptedDeletionIDs()
        XCTAssertEqual(repeatedDeletionIDs, [])
    }
}

private struct CloudSyncServiceFixture {
    let service: PingScopeCloudSyncService
    let boundary: RecordingCloudSyncBoundary
    let hostStore: LockedSharedHostStore
    let suiteName: String

    func cleanup() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

private func makeServiceFixture(
    hosts: [HostConfig],
    historyStore: any PingHistoryStore = InMemoryHistoryStore(),
    failingUploadAttempts: Set<Int> = [],
    unknownItemUploadAttempts: Set<Int> = [],
    hostStore suppliedHostStore: LockedSharedHostStore? = nil,
    suiteName suppliedSuiteName: String? = nil
) -> CloudSyncServiceFixture {
    let suiteName = suppliedSuiteName ?? "CloudSyncServiceTests-\(UUID().uuidString)"
    let hostStore = suppliedHostStore ?? LockedSharedHostStore(state: SharedHostStoreState(hosts: hosts))
    let boundary = RecordingCloudSyncBoundary(
        failingUploadAttempts: failingUploadAttempts,
        unknownItemUploadAttempts: unknownItemUploadAttempts
    )
    let service = PingScopeCloudSyncService(
        historyStore: historyStore,
        hostStore: hostStore,
        boundary: boundary,
        recordBuilder: DefaultCloudSyncRecordBuilder(),
        registrySuiteName: suiteName
    )
    return CloudSyncServiceFixture(
        service: service,
        boundary: boundary,
        hostStore: hostStore,
        suiteName: suiteName
    )
}

private final class LockedSharedHostStore: SharedHostStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SharedHostStoreState

    init(state: SharedHostStoreState) {
        self.state = state
    }

    func load() -> SharedHostStoreLoadResult {
        lock.withLock { SharedHostStoreLoadResult(state: state, source: .shared) }
    }

    func save(_ state: SharedHostStoreState) throws {
        lock.withLock { self.state = state }
    }
}

private actor InMemoryHistoryStore: PingHistoryStore {
    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private enum RecordingCloudSyncBoundaryError: Error {
    case transient
}

private actor RecordingCloudSyncBoundary: CloudSyncEngineBoundary {
    private let failingUploadAttempts: Set<Int>
    private let unknownItemUploadAttempts: Set<Int>
    private var attemptCount = 0
    private var successfulUploads: [[CKRecord]] = []
    private var successfulDeletions: [[CKRecord.ID]] = []
    private var attemptedDeletions: [[CKRecord.ID]] = []

    init(
        failingUploadAttempts: Set<Int>,
        unknownItemUploadAttempts: Set<Int> = []
    ) {
        self.failingUploadAttempts = failingUploadAttempts
        self.unknownItemUploadAttempts = unknownItemUploadAttempts
    }

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }
    func start() async throws {}
    func stop() async {}

    func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws {
        attemptCount += 1
        attemptedDeletions.append(deletions)
        if failingUploadAttempts.contains(attemptCount) {
            throw RecordingCloudSyncBoundaryError.transient
        }
        if unknownItemUploadAttempts.contains(attemptCount) {
            throw CKError(.unknownItem)
        }
        successfulUploads.append(records)
        successfulDeletions.append(deletions)
    }

    func resetUploads() {
        successfulUploads.removeAll()
        successfulDeletions.removeAll()
        attemptedDeletions.removeAll()
    }

    func uploadCallCount() -> Int { successfulUploads.count }

    func uploadedHostVersions() -> [CloudSyncHostVersion] {
        successfulUploads.flatMap { records in
            records.compactMap(MonitoredHostRecordMapper.monitoredHost(from:)).map {
                CloudSyncHostVersion(config: $0.config, modifiedAt: $0.modifiedAt)
            }
        }
    }

    func uploadedDeletionIDs() -> [UUID] {
        successfulDeletions.flatMap { $0 }.compactMap { UUID(uuidString: $0.recordName) }
    }

    func attemptedDeletionIDs() -> [UUID] {
        attemptedDeletions.flatMap { $0 }.compactMap { UUID(uuidString: $0.recordName) }
    }
}

private enum FakeCloudSyncBoundaryError: Error {
    case teardownFailed
}

private struct RealBoundaryFixture {
    let boundary: CKSyncEngineBoundary
    let host: RecordingCloudKitEngineHost
    let subscriptionID: CKSubscription.ID
}

private func makeRealBoundaryFixture(deleteError: CKError? = nil) -> RealBoundaryFixture {
    let subscriptionID = "PingScope.CloudSync.PrivateDatabase"
    let host = RecordingCloudKitEngineHost(deleteError: deleteError)
    let boundary = CKSyncEngineBoundary(
        engineHost: host,
        stateKey: "CloudSyncBoundaryTests-\(UUID().uuidString)",
        subscriptionID: subscriptionID
    )
    return RealBoundaryFixture(boundary: boundary, host: host, subscriptionID: subscriptionID)
}

private func assertBoundaryIsInactive(
    _ boundary: CKSyncEngineBoundary,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await boundary.upload(records: [], deletions: [])
        XCTFail("Expected stopped boundary to reject upload", file: file, line: line)
    } catch {
        // Any thrown error proves the real boundary released its active handle.
    }
}

private enum RecordingCloudKitEngineHostEvent: Equatable, Sendable {
    case prepareResources
    case createEngine(subscriptionID: CKSubscription.ID)
    case addDatabaseChanges
    case addRecordChanges
    case sendChanges
    case fetchChanges
    case cancel
    case deleteSubscription(CKSubscription.ID)
    case release
}

private final class RecordingCloudKitEngineHost: CloudKitEngineHosting, @unchecked Sendable {
    private let deleteError: CKError?
    private let lock = NSLock()
    private var recordedEvents: [RecordingCloudKitEngineHostEvent] = []
    private var activeHandles: Set<CloudKitEngineHandle> = []

    init(deleteError: CKError?) {
        self.deleteError = deleteError
    }

    func prepareResources() {
        lock.withLock {
            recordedEvents.append(.prepareResources)
        }
    }

    func accountAvailability() async -> CloudSyncAccountAvailability {
        .privateAccount
    }

    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) -> CloudKitEngineHandle {
        let handle = CloudKitEngineHandle()
        lock.withLock {
            activeHandles.insert(handle)
            recordedEvents.append(.createEngine(subscriptionID: subscriptionID))
        }
        return handle
    }

    func addPendingDatabaseChanges(
        _ changes: [CKSyncEngine.PendingDatabaseChange],
        to handle: CloudKitEngineHandle
    ) {
        lock.withLock {
            guard activeHandles.contains(handle) else { return }
            recordedEvents.append(.addDatabaseChanges)
        }
    }

    func addPendingRecordZoneChanges(
        _ changes: [CKSyncEngine.PendingRecordZoneChange],
        to handle: CloudKitEngineHandle
    ) {
        lock.withLock {
            guard activeHandles.contains(handle) else { return }
            recordedEvents.append(.addRecordChanges)
        }
    }

    func sendChanges(on handle: CloudKitEngineHandle) async throws {
        lock.withLock {
            guard activeHandles.contains(handle) else { return }
            recordedEvents.append(.sendChanges)
        }
    }

    func fetchChanges(on handle: CloudKitEngineHandle) async throws {
        lock.withLock {
            guard activeHandles.contains(handle) else { return }
            recordedEvents.append(.fetchChanges)
        }
    }

    func cancelOperations(on handle: CloudKitEngineHandle) async {
        lock.withLock {
            guard activeHandles.contains(handle) else { return }
            recordedEvents.append(.cancel)
        }
    }

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws {
        lock.withLock {
            recordedEvents.append(.deleteSubscription(subscriptionID))
        }
        if let deleteError { throw deleteError }
    }

    func releaseEngine(_ handle: CloudKitEngineHandle) {
        lock.withLock {
            guard activeHandles.remove(handle) != nil else { return }
            recordedEvents.append(.release)
        }
    }

    func events() async -> [RecordingCloudKitEngineHostEvent] {
        lock.withLock { recordedEvents }
    }

    func deletedSubscriptionIDs() async -> [CKSubscription.ID] {
        lock.withLock {
            recordedEvents.compactMap { event in
                guard case let .deleteSubscription(id) = event else { return nil }
                return id
            }
        }
    }
}

private enum FakeCloudSyncBoundaryLifecycleEvent: Equatable, Sendable {
    case tearDownSubscription
    case stop
}

private actor FakeCloudSyncBoundary: CloudSyncEngineBoundary {
    let availability: CloudSyncAccountAvailability
    let subscriptionTeardownError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var subscriptionTeardownCount = 0
    private(set) var uploadedRecordCount = 0
    private(set) var lifecycleEvents: [FakeCloudSyncBoundaryLifecycleEvent] = []

    init(
        availability: CloudSyncAccountAvailability,
        subscriptionTeardownError: (any Error)? = nil
    ) {
        self.availability = availability
        self.subscriptionTeardownError = subscriptionTeardownError
    }

    func accountAvailability() async -> CloudSyncAccountAvailability { availability }
    func start() async throws { startCount += 1 }
    func tearDownSubscriptions() async throws {
        subscriptionTeardownCount += 1
        lifecycleEvents.append(.tearDownSubscription)
        if let subscriptionTeardownError { throw subscriptionTeardownError }
    }
    func stop() async {
        do {
            try await tearDownSubscriptions()
        } catch {
            // Mirrors the live boundary's best-effort stop semantics.
        }
        stopCount += 1
        lifecycleEvents.append(.stop)
    }
    func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws {
        uploadedRecordCount += records.count
    }

    func stats() -> (
        startCount: Int,
        stopCount: Int,
        subscriptionTeardownCount: Int,
        uploadedRecordCount: Int,
        lifecycleEvents: [FakeCloudSyncBoundaryLifecycleEvent]
    ) {
        (startCount, stopCount, subscriptionTeardownCount, uploadedRecordCount, lifecycleEvents)
    }
}

private actor CountingCloudSyncRecordBuilder: CloudSyncRecordBuilding {
    private(set) var recordCount = 0

    func sampleRecord(from sample: PingResult) async -> CKRecord {
        recordCount += 1
        return PingSampleRecordMapper.record(from: sample)
    }

    func hostRecord(from host: CloudSyncHostVersion) async throws -> CKRecord {
        recordCount += 1
        return try MonitoredHostRecordMapper.record(from: host.config, modifiedAt: host.modifiedAt)
    }

    func count() -> Int { recordCount }
}

private actor SuspendingCloudSyncBoundary: CloudSyncEngineBoundary {
    private var stops = 0
    private var uploads = 0

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }
    func start() async throws { try await Task.sleep(for: .milliseconds(50)) }
    func stop() async { stops += 1 }
    func upload(records: [CKRecord], deletions: [CKRecord.ID]) async throws { uploads += 1 }
    func stopCount() -> Int { stops }
    func uploadCount() -> Int { uploads }
}
