import CloudKit
import Foundation
import XCTest
import PingScopeCore
@testable import PingScopeCloudSync

final class CloudSyncDrainHardeningTests: XCTestCase {
    func testTrickledDurableSamplesAccumulateIntoOneDrainBatch() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let samples = (0..<3).map { offset in
            PingResult.success(hostID: UUID(), latency: .milliseconds(Double(offset + 1)))
        }

        await service.setEnabled(true, hosts: [])
        for sample in samples {
            try await history.appendAndWait([sample])
            await service.samplesDidBecomeDurable()
        }
        await sleeper.waitForSleepStart()
        XCTAssertEqual(sleeper.pendingDelays(), [.milliseconds(10)])
        XCTAssertTrue(sleeper.releaseNext())
        await boundary.waitForSampleBatchCount(1)
        await history.waitForUnsyncedQueueToEmpty()

        let batches = await boundary.sampleBatches()
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(Set(batches[0]), Set(samples.map(\.id)))
        await service.setEnabled(false, hosts: [])
    }

    func testUnknownSampleWithShortRetryAfterWaitsAtLeastDefaultRetryDelay() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let shortRetryAfter = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let unknown = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([
            shortRetryAfter.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 0.01])]
        ])
        await boundary.setUnknownSampleIDs([unknown.id])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([shortRetryAfter, unknown])
        _ = await service.uploadSamples([shortRetryAfter, unknown])
        await sleeper.waitForSleepStart()

        XCTAssertEqual(sleeper.pendingDelays(), [.seconds(1)])
        await service.setEnabled(false, hosts: [])
    }

    func testFallbackRetryDelayWidensExponentially() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = RecordingCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            sample.id: [
                CKError(.networkUnavailable),
                CKError(.networkUnavailable),
                CKError(.networkUnavailable)
            ]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForDelayCount(3)

        let delays = await sleeper.delays()
        XCTAssertEqual(delays, [.seconds(1), .seconds(2), .seconds(4)])
        await service.setEnabled(false, hosts: [])
    }

    func testDurableAppendsDuringPersistentFailureDoNotResetExponentialBackoff() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = GatedBackoffRecordingSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let poison = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            poison.id: Array(repeating: CKError(.requestRateLimited), count: 8)
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([poison])
        _ = await service.uploadSamples([poison])
        await sleeper.waitForBackoffCount(1)

        for expectedCount in 2...7 {
            let fresh = PingResult.success(hostID: UUID(), latency: .milliseconds(Double(expectedCount)))
            try await history.appendAndWait([fresh])
            await service.samplesDidBecomeDurable()
            await sleeper.waitForBackoffCount(expectedCount)
        }

        let delays = sleeper.backoffDelays()
        XCTAssertEqual(
            delays,
            [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)]
        )
        await service.setEnabled(false, hosts: [])
    }

    func testShortServerRetryAfterCannotBypassExponentialFallback() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([
            sample.id: [CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 0.01])]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForSleepStart()

        XCTAssertEqual(sleeper.pendingDelays(), [.seconds(1)])
        await service.setEnabled(false, hosts: [])
    }

    func testInjectedSleeperCapsFallbackRetryAtSixtySeconds() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = RecordingCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            sample.id: Array(repeating: CKError(.networkUnavailable), count: 7)
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForDelayCount(7)

        let delays = await sleeper.delays()
        XCTAssertEqual(delays, [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)])
        await service.setEnabled(false, hosts: [])
    }

    func testSampleDrainSplitsThreeHundredOneSamplesIntoTwoBatches() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let service = makeService(history: history, boundary: boundary)
        let samples = (0..<301).map { index in
            PingResult.success(hostID: UUID(), latency: .milliseconds(Double(index + 1)))
        }

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait(samples)
        _ = await service.uploadSamples(samples)

        let batches = await boundary.sampleBatches()
        XCTAssertEqual(batches.map(\.count), [300, 1])
        XCTAssertEqual(batches.flatMap { $0 }, samples.map(\.id))
        await service.setEnabled(false, hosts: [])
    }

    func testMixedRetryAfterMetadataHonorsTheLongestServerDelay() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = RecordingCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let shorterDelay = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let longerDelay = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        let fallbackDelay = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            shorterDelay.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 1.0])],
            longerDelay.id: [CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 5.0])],
            fallbackDelay.id: [CKError(.networkUnavailable)]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([shorterDelay, longerDelay, fallbackDelay])
        _ = await service.uploadSamples([shorterDelay, longerDelay, fallbackDelay])
        try await waitForDrain { await history.unsyncedIDs().isEmpty }

        let delays = await sleeper.delays()
        XCTAssertEqual(delays.first, .seconds(5))
        await service.setEnabled(false, hosts: [])
    }

    func testAccountLossCancelsPendingRetryBeforeRecoveryCompletes() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            sample.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 5.0])]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForSleepStart()

        await boundary.setAvailability(.unavailable)
        await boundary.emitAccountChange()

        let status = await service.status()
        let batches = await boundary.sampleBatches()
        let unsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(sleeper.pendingDelays(), [])
        XCTAssertEqual(status, .accountUnavailable)
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(unsyncedIDs, [sample.id])
        await service.setEnabled(false, hosts: [])
    }

    func testFreshDurableSignalDuringSuspendedUploadPrioritizesDrainOverRetry() async throws {
        let history = DrainHardeningOutbox()
        let boundary = SuspendedRetryBoundary()
        let sleeper = ManualCloudSleeper()
        let service = PingScopeCloudSyncService(
            historyStore: history,
            hostStore: DrainHardeningHostStore(hosts: []),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: "CloudSyncSuspendedRetry-\(UUID().uuidString)",
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let first = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let fresh = PingResult.success(hostID: UUID(), latency: .milliseconds(4))

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([first])
        let initialUpload = Task { await service.uploadSamples([first]) }
        await boundary.waitForFirstUpload()

        try await history.appendAndWait([fresh])
        await service.samplesDidBecomeDurable()
        await boundary.releaseFirstUpload()
        _ = await initialUpload.value

        let batches = await boundary.sampleBatches()
        XCTAssertEqual(batches, [[first.id], [first.id, fresh.id]])
        XCTAssertEqual(sleeper.pendingDelays(), [])
        await service.setEnabled(false, hosts: [])
    }

    func testPermanentRecordFailureIsTerminalWhileHealthyRecordIsConfirmed() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let service = makeService(history: history, boundary: boundary)
        let healthy = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let poison = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([poison.id: [CKError(.invalidArguments)]])

        await service.setEnabled(true, hosts: [])
        try await append([healthy, poison], to: history, service: service)
        try await waitForDrain { await history.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleBatches()
        let acknowledgedIDs = await history.acknowledgedIDs()
        XCTAssertEqual(batches, [[healthy.id, poison.id]])
        XCTAssertEqual(Set(acknowledgedIDs), Set([healthy.id, poison.id]))
        await service.setEnabled(false, hosts: [])
    }

    func testTransientPartialFailureRetriesAfterBoundedRetryAfterWithoutAppend() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = RecordingCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let healthy = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let delayed = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        let retryAfter = 0.03
        await boundary.setFailures([
            delayed.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: retryAfter])]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([healthy, delayed])
        _ = await service.uploadSamples([healthy, delayed])
        await sleeper.waitForDelayCount(1)
        _ = await service.uploadSamples([])

        let batches = await boundary.sampleBatches()
        XCTAssertEqual(Set(batches[0]), Set([healthy.id, delayed.id]))
        XCTAssertEqual(batches[1], [delayed.id])
        let delays = await sleeper.delays()
        XCTAssertEqual(delays, [.seconds(1)])
        await service.setEnabled(false, hosts: [])
    }

    func testAccountTemporarilyUnavailableWaitsForAccountRecoveryInsteadOfPolling() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([
            sample.id: [CKError(.accountTemporarilyUnavailable)]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])

        let batches = await boundary.sampleBatches()
        let unsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(unsyncedIDs, [sample.id])
        XCTAssertEqual(sleeper.pendingDelays(), [])
        await service.setEnabled(false, hosts: [])
    }

    func testOperationCancelledRecordRemainsInOutboxWithoutImmediateRetry() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([
            sample.id: [CKError(.operationCancelled)]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])

        let batches = await boundary.sampleBatches()
        let unsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(unsyncedIDs, [sample.id])
        XCTAssertEqual(sleeper.pendingDelays(), [])
        await service.setEnabled(false, hosts: [])
    }

    func testDeferredRecordFailureStillAcknowledgesHealthyRecordsInTheBatch() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let service = makeService(history: history, boundary: boundary)
        let healthy = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        let deferred = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([deferred.id: [CKError(.operationCancelled)]])

        await service.setEnabled(true, hosts: [])
        try await append([healthy, deferred], to: history, service: service)
        try await waitForDrain { await history.unsyncedIDs() == [deferred.id] }

        let batches = await boundary.sampleBatches()
        let acknowledgedIDs = await history.acknowledgedIDs()
        XCTAssertEqual(batches, [[healthy.id, deferred.id]])
        XCTAssertEqual(acknowledgedIDs, [healthy.id])
        await service.setEnabled(false, hosts: [])
    }

    func testOneSecondRetryAfterIsNotCollapsedToSubsecondBackoff() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = RecordingCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        await boundary.setFailures([
            sample.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 1.0])]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForDelayCount(1)

        let delays = await sleeper.delays()
        XCTAssertEqual(delays, [.seconds(1)])
        await service.setEnabled(false, hosts: [])
    }

    func testWholeOperationFailureWithoutCloudKitRetryMetadataLeavesOutboxUntouched() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let service = makeService(history: history, boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(4))

        await service.setEnabled(true, hosts: [])
        await boundary.failWholeUploads(count: 1)
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])

        let batches = await boundary.sampleBatches()
        let unsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(unsyncedIDs, [sample.id])
        await service.setEnabled(false, hosts: [])
    }

    func testDisablingCancelsScheduledRetry() async throws {
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let sleeper = ManualCloudSleeper()
        let service = makeService(
            history: history,
            boundary: boundary,
            sleep: { duration in try await sleeper.sleep(for: duration) }
        )
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await boundary.setFailures([
            sample.id: [CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 1.0])]
        ])

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        _ = await service.uploadSamples([sample])
        await sleeper.waitForSleepStart()
        await service.setEnabled(false, hosts: [])

        let batches = await boundary.sampleBatches()
        let unsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(unsyncedIDs, [sample.id])
        XCTAssertEqual(sleeper.pendingDelays(), [])
    }

    func testRedundantEnableReconcilesChangedHostsBeforeDrainingSamples() async throws {
        let original = HostConfig(displayName: "Original", address: "old.example")
        let changed = HostConfig(
            id: original.id,
            displayName: "Changed",
            address: "new.example",
            method: original.method,
            port: original.port,
            interval: original.interval,
            timeout: original.timeout,
            thresholds: original.thresholds,
            isEnabled: original.isEnabled
        )
        let history = DrainHardeningOutbox()
        let boundary = DrainHardeningBoundary()
        let service = makeService(history: history, boundary: boundary, hosts: [original])

        await service.setEnabled(true, hosts: [original])
        try await waitForDrain { await boundary.hostConfigs().count == 1 }
        await service.setEnabled(true, hosts: [changed])
        try await waitForDrain { await boundary.hostConfigs().count == 2 }

        let reconciledHosts = await boundary.hostConfigs()
        XCTAssertEqual(reconciledHosts.last, changed)
        await service.setEnabled(true, hosts: [changed])
        let hostUploadCount = await boundary.hostConfigs().count
        XCTAssertEqual(hostUploadCount, 2)
        await service.setEnabled(false, hosts: [])
    }

    func testInitialUnavailableAccountRecoveryAutomaticallyDrainsBacklog() async throws {
        let history = DrainHardeningOutbox()
        let boundary = RecoveryDrainBoundary(availability: .unavailable)
        let host = HostConfig(displayName: "Recovery host", address: "recovery.example")
        let service = makeRecoveryService(history: history, boundary: boundary, hosts: [host])
        let sample = PingResult.success(hostID: host.id, latency: .milliseconds(6))
        try await history.appendAndWait([sample])

        await service.setEnabled(true, hosts: [host])
        let initialUnsyncedIDs = await history.unsyncedIDs()
        XCTAssertEqual(initialUnsyncedIDs, [sample.id])

        await boundary.setAvailability(.privateAccount)
        await boundary.emitAccountChange()
        try await waitForDrain { await history.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleBatches()
        let hostConfigs = await boundary.hostConfigs()
        XCTAssertEqual(batches, [[sample.id]])
        XCTAssertEqual(hostConfigs, [host])
        await service.setEnabled(false, hosts: [])
    }

    func testActiveAccountRecoveryAutomaticallyDrainsBacklogQueuedWhileUnavailable() async throws {
        let history = DrainHardeningOutbox()
        let boundary = RecoveryDrainBoundary(availability: .privateAccount)
        let service = makeRecoveryService(history: history, boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(6))

        await service.setEnabled(true, hosts: [])
        await boundary.setAvailability(.unavailable)
        await boundary.emitAccountChange()
        try await waitForDrain { await service.status() == .accountUnavailable }
        try await history.appendAndWait([sample])

        await boundary.setAvailability(.privateAccount)
        await boundary.emitAccountChange()
        try await waitForDrain { await history.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleBatches()
        XCTAssertEqual(batches, [[sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testAccountSwitchClearsOldLocalAcknowledgementAndReuploadsToNewAccount() async throws {
        let history = DrainHardeningOutbox()
        let boundary = RecoveryDrainBoundary(availability: .privateAccount)
        let service = makeRecoveryService(history: history, boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(6))
        await history.failNextMarkAttempts(3)

        await service.setEnabled(true, hosts: [])
        try await history.appendAndWait([sample])
        await service.samplesDidBecomeDurable()
        try await waitForDrain { await history.markAttemptCount() == 3 }
        let oldAccountBatches = await boundary.sampleBatches()
        let unsyncedBeforeSwitch = await history.unsyncedIDs()
        XCTAssertEqual(oldAccountBatches, [[sample.id]])
        XCTAssertEqual(unsyncedBeforeSwitch, [sample.id])

        await boundary.emitAccountChange()
        try await waitForDrain { await history.unsyncedIDs().isEmpty }

        let allAccountBatches = await boundary.sampleBatches()
        XCTAssertEqual(allAccountBatches, [[sample.id], [sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    private func makeService(
        history: DrainHardeningOutbox,
        boundary: DrainHardeningBoundary,
        hosts: [HostConfig] = [],
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> PingScopeCloudSyncService {
        PingScopeCloudSyncService(
            historyStore: history,
            hostStore: DrainHardeningHostStore(hosts: hosts),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: "CloudSyncDrainHardening-\(UUID().uuidString)",
            sleep: sleep
        )
    }

    private func append(
        _ samples: [PingResult],
        to history: DrainHardeningOutbox,
        service: PingScopeCloudSyncService
    ) async throws {
        try await history.appendAndWait(samples)
        await service.samplesDidBecomeDurable()
    }

    private func makeRecoveryService(
        history: DrainHardeningOutbox,
        boundary: RecoveryDrainBoundary,
        hosts: [HostConfig] = []
    ) -> PingScopeCloudSyncService {
        PingScopeCloudSyncService(
            historyStore: history,
            hostStore: DrainHardeningHostStore(hosts: hosts),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: "CloudSyncRecoveryDrainHardening-\(UUID().uuidString)"
        )
    }
}

private actor DrainHardeningOutbox: PingHistoryStore {
    private var values: [UUID: PingResult] = [:]
    private var order: [UUID] = []
    private var acknowledged: [UUID] = []
    private var emptyQueueWaiters: [CheckedContinuation<Void, Never>] = []
    private var remainingMarkFailures = 0
    private var markAttempts = 0

    func append(_ result: PingResult) async { appendLocally([result]) }
    func append(_ results: [PingResult]) async { appendLocally(results) }
    func appendAndWait(_ results: [PingResult]) async throws { appendLocally(results) }
    func unsyncedSamples(limit: Int) async throws -> [PingResult] { order.prefix(limit).compactMap { values[$0] } }
    func markSamplesSynced(ids: [UUID]) async throws {
        markAttempts += 1
        if remainingMarkFailures > 0 {
            remainingMarkFailures -= 1
            throw DrainHardeningOutboxError.forcedMarkFailure
        }
        acknowledged.append(contentsOf: ids)
        let ids = Set(ids)
        order.removeAll { ids.contains($0) }
        guard order.isEmpty else { return }
        let waiters = emptyQueueWaiters
        emptyQueueWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func unsyncedIDs() -> [UUID] { order }
    func acknowledgedIDs() -> [UUID] { acknowledged }
    func failNextMarkAttempts(_ count: Int) { remainingMarkFailures = count }
    func markAttemptCount() -> Int { markAttempts }
    func waitForUnsyncedQueueToEmpty() async {
        guard !order.isEmpty else { return }
        await withCheckedContinuation { emptyQueueWaiters.append($0) }
    }

    private func appendLocally(_ samples: [PingResult]) {
        for sample in samples where values.updateValue(sample, forKey: sample.id) == nil {
            order.append(sample.id)
        }
    }
}

private enum DrainHardeningOutboxError: Error {
    case forcedMarkFailure
}

private actor DrainHardeningBoundary: CloudSyncEngineBoundary {
    private var failuresBySampleID: [UUID: [CKError]] = [:]
    private var sampleBatchesStorage: [[UUID]] = []
    private var sampleAttemptDatesStorage: [Date] = []
    private var hostConfigsStorage: [HostConfig] = []
    private var remainingWholeUploadFailures = 0
    private var unknownSampleIDs: Set<UUID> = []
    private var sampleBatchWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var availability: CloudSyncAccountAvailability = .privateAccount
    private var accountChangeHandler: (@Sendable () async -> Void)?

    func accountAvailability() async -> CloudSyncAccountAvailability { availability }
    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async {
        accountChangeHandler = handler
    }
    func start() async throws {}
    func stop() async {}

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        let sampleRecords = records.filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
        let sampleIDs = sampleRecords.compactMap { UUID(uuidString: $0.recordID.recordName) }
        if !sampleIDs.isEmpty {
            sampleBatchesStorage.append(sampleIDs)
            sampleAttemptDatesStorage.append(Date())
            let waiters = sampleBatchWaiters.filter { sampleBatchesStorage.count >= $0.count }
            sampleBatchWaiters.removeAll { sampleBatchesStorage.count >= $0.count }
            waiters.forEach { $0.continuation.resume() }
        }
        if remainingWholeUploadFailures > 0 {
            remainingWholeUploadFailures -= 1
            throw DrainHardeningBoundaryError.forced
        }
        for record in records where record.recordType == PingScopeCloudKitModel.RecordType.monitoredHost {
            if let host = MonitoredHostRecordMapper.monitoredHost(from: record)?.config {
                hostConfigsStorage.append(host)
            }
        }

        let requested = Set(records.map(\.recordID))
        var failures: [CKRecord.ID: CKError] = [:]
        for record in sampleRecords {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  var scriptedErrors = failuresBySampleID[id],
                  !scriptedErrors.isEmpty else { continue }
            failures[record.recordID] = scriptedErrors.removeFirst()
            failuresBySampleID[id] = scriptedErrors
        }
        return CloudSyncUploadConfirmation(
            requestedRecordIDs: requested,
            confirmedRecordIDs: requested
                .subtracting(Set(failures.keys))
                .subtracting(Set(sampleRecords.filter {
                    UUID(uuidString: $0.recordID.recordName).map(unknownSampleIDs.contains) ?? false
                }.map(\.recordID))),
            failedRecordSaveErrors: failures
        )
    }

    func setFailures(_ values: [UUID: [CKError]]) { failuresBySampleID = values }
    func setUnknownSampleIDs(_ ids: Set<UUID>) { unknownSampleIDs = ids }
    func failWholeUploads(count: Int) { remainingWholeUploadFailures = count }
    func setAvailability(_ availability: CloudSyncAccountAvailability) { self.availability = availability }
    func emitAccountChange() async {
        let handler = accountChangeHandler
        await handler?()
    }
    func sampleBatches() -> [[UUID]] { sampleBatchesStorage }
    func waitForSampleBatchCount(_ count: Int) async {
        guard sampleBatchesStorage.count < count else { return }
        await withCheckedContinuation { sampleBatchWaiters.append((count, $0)) }
    }
    func sampleAttemptDates() -> [Date] { sampleAttemptDatesStorage }
    func hostConfigs() -> [HostConfig] { hostConfigsStorage }
}

private enum DrainHardeningBoundaryError: Error {
    case forced
}

private actor RecordingCloudSleeper {
    private var recordedDelays: [Duration] = []
    private var delayCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async throws {
        recordedDelays.append(duration)
        let readyWaiters = delayCountWaiters.filter { recordedDelays.count >= $0.count }
        delayCountWaiters.removeAll { recordedDelays.count >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }

    func delays() -> [Duration] { recordedDelays }

    func waitForDelayCount(_ count: Int) async {
        guard recordedDelays.count < count else { return }
        await withCheckedContinuation { continuation in
            delayCountWaiters.append((count, continuation))
        }
    }
}

private final class GatedBackoffRecordingSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var recordedDelays: [Duration] = []
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async throws {
        guard duration >= .seconds(1) else { return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                recordedDelays.append(duration)
                pending[id] = continuation
                let ready = countWaiters.filter { recordedDelays.count >= $0.count }
                countWaiters.removeAll { recordedDelays.count >= $0.count }
                lock.unlock()
                ready.forEach { $0.continuation.resume() }
            }
        }, onCancel: {
            self.cancel(id: id)
        })
    }

    func waitForBackoffCount(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if recordedDelays.count >= count {
                lock.unlock()
                continuation.resume()
                return
            }
            countWaiters.append((count, continuation))
            lock.unlock()
        }
    }

    func backoffDelays() -> [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDelays
    }

    private func cancel(id: UUID) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private final class ManualCloudSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UUID: (continuation: CheckedContinuation<Void, Error>, delay: Duration)] = [:]
    private var sleepStartWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending[id] = (continuation, duration)
                let waiters = sleepStartWaiters
                sleepStartWaiters.removeAll()
                lock.unlock()
                waiters.forEach { $0.resume() }
            }
        }, onCancel: {
            self.cancel(id: id)
        })
    }

    func waitForSleepStart() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !pending.isEmpty {
                lock.unlock()
                continuation.resume()
                return
            }
            sleepStartWaiters.append(continuation)
            lock.unlock()
        }
    }

    func pendingDelays() -> [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return pending.values.map(\.delay)
    }

    func releaseNext() -> Bool {
        lock.lock()
        guard let id = pending.keys.first,
              let continuation = pending.removeValue(forKey: id)?.continuation else {
            lock.unlock()
            return false
        }
        lock.unlock()
        continuation.resume()
        return true
    }

    private func cancel(id: UUID) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)?.continuation
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private actor SuspendedRetryBoundary: CloudSyncEngineBoundary {
    private var batches: [[UUID]] = []
    private var firstUploadContinuation: CheckedContinuation<Void, Never>?
    private var firstUploadWaiters: [CheckedContinuation<Void, Never>] = []

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }
    func start() async throws {}
    func stop() async {}

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        _ = deletions
        let ids = records
            .filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
            .compactMap { UUID(uuidString: $0.recordID.recordName) }
        guard !ids.isEmpty else {
            return CloudSyncUploadConfirmation(confirming: records)
        }
        batches.append(ids)
        if batches.count == 1 {
            let waiters = firstUploadWaiters
            firstUploadWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstUploadContinuation = continuation
            }
            throw CKError(.networkFailure, userInfo: [CKErrorRetryAfterKey: 5.0])
        }
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func waitForFirstUpload() async {
        guard batches.count < 1 else { return }
        await withCheckedContinuation { firstUploadWaiters.append($0) }
    }

    func releaseFirstUpload() {
        let continuation = firstUploadContinuation
        firstUploadContinuation = nil
        continuation?.resume()
    }

    func sampleBatches() -> [[UUID]] { batches }
}

private actor RecoveryDrainBoundary: CloudSyncEngineBoundary {
    private var availability: CloudSyncAccountAvailability
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var batches: [[UUID]] = []
    private var uploadedHosts: [HostConfig] = []

    init(availability: CloudSyncAccountAvailability) {
        self.availability = availability
    }

    func accountAvailability() async -> CloudSyncAccountAvailability { availability }
    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async {
        accountChangeHandler = handler
    }
    func start() async throws {}
    func stop() async {}

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        let ids = records
            .filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
            .compactMap { UUID(uuidString: $0.recordID.recordName) }
        if !ids.isEmpty { batches.append(ids) }
        for record in records where record.recordType == PingScopeCloudKitModel.RecordType.monitoredHost {
            if let host = MonitoredHostRecordMapper.monitoredHost(from: record)?.config {
                uploadedHosts.append(host)
            }
        }
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func setAvailability(_ availability: CloudSyncAccountAvailability) {
        self.availability = availability
    }

    func emitAccountChange() async {
        let handler = accountChangeHandler
        await handler?()
    }

    func sampleBatches() -> [[UUID]] { batches }
    func hostConfigs() -> [HostConfig] { uploadedHosts }
}

private final class DrainHardeningHostStore: SharedHostStoring, @unchecked Sendable {
    private let hosts: [HostConfig]

    init(hosts: [HostConfig]) { self.hosts = hosts }

    func load() -> SharedHostStoreLoadResult {
        SharedHostStoreLoadResult(state: SharedHostStoreState(hosts: hosts), source: .shared)
    }

    func save(_ state: SharedHostStoreState) throws { _ = state }
}

private func waitForDrain(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        guard clock.now < deadline else {
            XCTFail("Timed out waiting for cloud drain")
            throw DrainHardeningWaitError.timedOut
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private enum DrainHardeningWaitError: Error {
    case timedOut
}
