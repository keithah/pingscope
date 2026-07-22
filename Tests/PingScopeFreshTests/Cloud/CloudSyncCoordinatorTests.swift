import CloudKit
import XCTest
import PingScopeCore
import PingScopeObjCExceptionBoundary
@testable import PingScopeCloudSync

// SwiftPM tests cover CKSyncEngineBoundary orchestration through an injected
// CloudKitEngineHosting edge. The production adapter's entitled CKContainer,
// live send/fetch, and subscription deletion require an on-device/Xcode smoke.

final class CloudSyncCoordinatorTests: XCTestCase {
    func testMonitoredHostRecordRoundTripPreservesDisplayColorInsideConfigJSON() throws {
        let config = HostConfig(
            id: UUID(),
            displayName: "DNS",
            address: "1.1.1.1",
            displayColor: HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        )

        let record = try MonitoredHostRecordMapper.record(from: config, modifiedAt: .now)
        let mapped = try XCTUnwrap(MonitoredHostRecordMapper.monitoredHost(from: record))

        XCTAssertEqual(mapped.config.displayColor, config.displayColor)
    }

    func testMonitoredHostRecordDecodesMalformedDisplayColorAsAutomaticWithoutDroppingHost() throws {
        let config = HostConfig(id: UUID(), displayName: "DNS", address: "1.1.1.1")
        let record = try MonitoredHostRecordMapper.record(from: config, modifiedAt: .now)
        let configData = try XCTUnwrap(record[PingScopeCloudKitModel.MonitoredHostField.configJSON] as? Data)
        var configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        configObject["displayColor"] = ["red": 0.2, "green": 0.4]
        record[PingScopeCloudKitModel.MonitoredHostField.configJSON] = try JSONSerialization.data(withJSONObject: configObject) as CKRecordValue

        let mapped = try XCTUnwrap(MonitoredHostRecordMapper.monitoredHost(from: record))

        XCTAssertEqual(mapped.config, config)
        XCTAssertNil(mapped.config.displayColor)
    }

    func testAccountAvailabilityFailureBecomesFailedStatusWithoutStartingEngine() async {
        let boundary = ThrowingAvailabilityCloudSyncBoundary()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)

        await coordinator.setEnabled(true)

        let status = await coordinator.status
        let startCallCount = await boundary.startCallCount()
        XCTAssertEqual(status, .failed("missingContainerEntitlement"))
        XCTAssertEqual(startCallCount, 0)
    }

    func testLiveCloudKitHostPropagatesDefaultContainerProviderFailure() {
        let host = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Missing",
            containerProvider: ThrowingCloudKitContainerProvider()
        )

        XCTAssertThrowsError(try host.prepareResources()) { error in
            XCTAssertEqual(
                error as? CloudSyncBoundaryError,
                .missingContainerEntitlement("iCloud.com.example.Missing")
            )
        }
    }

    func testLiveCloudKitHostMapsInjectedAccountStatusWithoutConstructingContainer() async throws {
        let availableHost = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Unconstructed",
            containerProvider: ThrowingCloudKitContainerProvider(),
            accountStatus: { .available }
        )
        let unavailableHost = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Unconstructed",
            containerProvider: ThrowingCloudKitContainerProvider(),
            accountStatus: { .noAccount }
        )

        let available = try await availableHost.accountAvailability()
        let unavailable = try await unavailableHost.accountAvailability()

        XCTAssertEqual(available, .privateAccount)
        XCTAssertEqual(unavailable, .unavailable)
    }

    func testLiveCloudKitHostPropagatesTransientAccountStatusFailure() async {
        let host = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Unconstructed",
            containerProvider: ThrowingCloudKitContainerProvider(),
            accountStatus: { throw CKError(.networkFailure) }
        )

        do {
            _ = try await host.accountAvailability()
            XCTFail("Expected the transient account-status failure to be retried by the coordinator")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .networkFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveCloudKitHostPropagatesAccountStatusCancellation() async {
        let host = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Unconstructed",
            containerProvider: ThrowingCloudKitContainerProvider(),
            accountStatus: {
                try await Task.sleep(for: .seconds(60))
                return .available
            }
        )
        let task = Task { try await host.accountAvailability() }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not an account-unavailable state.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveCloudKitHostBoundsUnresponsiveAccountStatusCheck() async {
        let host = LiveCloudKitEngineHost(
            containerIdentifier: "iCloud.com.example.Unconstructed",
            containerProvider: ThrowingCloudKitContainerProvider(),
            accountStatus: {
                try await Task.sleep(for: .seconds(60))
                return .available
            },
            accountStatusTimeout: .milliseconds(20)
        )

        do {
            _ = try await host.accountAvailability()
            XCTFail("Expected a bounded account-status timeout")
        } catch let error as CloudSyncBoundaryError {
            XCTAssertEqual(error, .accountStatusTimedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultContainerProviderRejectsMissingEntitlementBeforeConstruction() {
        var didCreateContainer = false
        let provider = DefaultCloudKitContainerProvider(
            entitledContainerIdentifiers: { [] },
            makeDefaultContainer: {
                didCreateContainer = true
                return CKContainer.default()
            }
        )

        XCTAssertThrowsError(try provider.defaultContainer(for: "iCloud.com.example.Missing")) { error in
            XCTAssertEqual(
                error as? CloudSyncBoundaryError,
                .missingContainerEntitlement("iCloud.com.example.Missing")
            )
        }
        XCTAssertFalse(didCreateContainer)
    }

    func testDefaultContainerProviderConvertsDefaultContainerExceptionIntoMissingEntitlement() {
        let identifier = "iCloud.com.example.Misprovisioned"
        let provider = DefaultCloudKitContainerProvider(
            entitledContainerIdentifiers: { [identifier] },
            makeDefaultContainer: {
                NSException(
                    name: .internalInconsistencyException,
                    reason: "missing signed iCloud entitlement"
                ).raise()
                return CKContainer.default()
            }
        )

        XCTAssertThrowsError(try provider.defaultContainer(for: identifier)) { error in
            XCTAssertEqual(
                error as? CloudSyncBoundaryError,
                .missingContainerEntitlement(identifier)
            )
        }
    }

    func testObjCExceptionBoundaryReturnsNilWhenOperationRaises() {
        let result = PingScopePerformCatchingObjCException {
            NSException(
                name: .internalInconsistencyException,
                reason: "test exception"
            ).raise()
            return NSObject()
        }

        XCTAssertNil(result)
    }

    func testMisprovisionedDefaultContainerParksPersistedActivationDisabled() async {
        let identifier = "iCloud.com.example.Misprovisioned"
        let provider = DefaultCloudKitContainerProvider(
            entitledContainerIdentifiers: { [identifier] },
            makeDefaultContainer: {
                NSException(
                    name: .internalInconsistencyException,
                    reason: "missing signed iCloud entitlement"
                ).raise()
                return CKContainer.default()
            }
        )
        let engineHost = LiveCloudKitEngineHost(
            containerIdentifier: identifier,
            containerProvider: provider
        )
        let boundary = CKSyncEngineBoundary(
            engineHost: engineHost,
            stateKey: "CloudSyncMisprovisionedContainerTests",
            subscriptionID: "CloudSyncMisprovisionedContainerTests"
        )
        let suiteName = "CloudSyncMisprovisionedContainerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        let service = PingScopeCloudSyncService(
            historyStore: InMemoryHistoryStore(),
            hostStore: LockedSharedHostStore(state: SharedHostStoreState(hosts: [])),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName
        )

        let state = await activation.activatePersisted(hosts: [])

        XCTAssertFalse(state.isEnabled)
        XCTAssertTrue(state.statusText.contains("missingContainerEntitlement"))
    }

    func testDefaultContainerProviderRejectsUnsignedProcessWithoutConstructingCloudKit() {
        let provider = DefaultCloudKitContainerProvider()

        XCTAssertThrowsError(
            try provider.defaultContainer(for: PingScopeCloudKitModel.containerIdentifier)
        ) { error in
            XCTAssertEqual(
                error as? CloudSyncBoundaryError,
                .missingContainerEntitlement(PingScopeCloudKitModel.containerIdentifier)
            )
        }
    }

    func testFirstPersistedLaunchFailureKeepsPreferenceArmedForNextLaunch() async {
        let suiteName = "CloudSyncLaunchFailureTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        let boundary = ThrowingAvailabilityCloudSyncBoundary()
        let service = PingScopeCloudSyncService(
            historyStore: InMemoryHistoryStore(),
            hostStore: LockedSharedHostStore(state: SharedHostStoreState(hosts: [])),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName
        )

        let state = await activation.activatePersisted(hosts: [])

        XCTAssertFalse(state.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
        XCTAssertEqual(defaults.integer(forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey), 1)
        XCTAssertTrue(state.statusText.contains("retry"))
        XCTAssertTrue(state.statusText.contains("missingContainerEntitlement"))
    }

    func testAutomaticFailuresRetryUntilThresholdThenDisablePersistedPreference() async {
        let suiteName = "CloudSyncAutomaticRetryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        let service = RecordingActivationService(status: .failed("transient"))
        let maximumFailures = 3

        for expectedFailureCount in 1..<maximumFailures {
            let activation = PingScopeCloudSyncActivationController(
                service: service,
                defaultsSuiteName: suiteName,
                maximumAutomaticStartFailures: maximumFailures
            )
            let state = await activation.activatePersisted(hosts: [])

            XCTAssertFalse(state.isEnabled)
            XCTAssertTrue(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
            XCTAssertEqual(
                defaults.integer(forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey),
                expectedFailureCount
            )
        }

        let finalActivation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName,
            maximumAutomaticStartFailures: maximumFailures
        )
        _ = await finalActivation.activatePersisted(hosts: [])
        let enableCallCount = await service.enableCallCount()

        XCTAssertFalse(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
        XCTAssertEqual(enableCallCount, maximumFailures)
    }

    func testProcessDeathAfterPrearmedAttemptPreventsAnotherFatalRetryAtThreshold() async {
        let suiteName = "CloudSyncProcessDeathGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        // This is the durable state a process leaves when it dies after pre-arming
        // its third start attempt and before setEnabled(true) can return.
        defaults.set(3, forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey)
        let service = RecordingActivationService(status: .idle)
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName,
            maximumAutomaticStartFailures: 3
        )

        let state = await activation.activatePersisted(hosts: [])
        let enableCallCount = await service.enableCallCount()
        let disableCallCount = await service.disableCallCount()

        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
        XCTAssertEqual(enableCallCount, 0)
        XCTAssertEqual(disableCallCount, 1)
    }

    func testPersistedActivationDurablyPrearmsFailureCountBeforeEnteringService() async {
        let suiteName = "CloudSyncPrearmOrderingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        let service = GatedActivationService()
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName,
            maximumAutomaticStartFailures: 3
        )

        let automatic = Task { await activation.activatePersisted(hosts: []) }
        await service.waitForEnableCall()

        XCTAssertEqual(
            defaults.integer(forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey),
            1,
            "a hard process death at this point must leave a durable consumed attempt"
        )

        await service.releaseEnable(with: .idle)
        _ = await automatic.value
        XCTAssertEqual(
            defaults.integer(forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey),
            0
        )
    }

    func testUserDisableSupersedesInFlightAutomaticActivationWithoutRecordingFailure() async {
        let suiteName = "CloudSyncActivationGenerationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        let service = GatedActivationService()
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName
        )

        let automatic = Task { await activation.activatePersisted(hosts: []) }
        await service.waitForEnableCall()
        let disabled = await activation.setEnabledByUser(false, hosts: [])
        await service.releaseEnable(with: .failed("superseded"))
        _ = await automatic.value

        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
        XCTAssertEqual(
            defaults.integer(forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey),
            0
        )
    }

    func testRepeatedAutomaticStartFailuresStopFuturePersistedAutoEnable() async {
        let suiteName = "CloudSyncLaunchGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        defaults.set(
            PingScopeCloudSyncActivationController.defaultMaximumAutomaticStartFailures,
            forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey
        )
        let boundary = ThrowingAvailabilityCloudSyncBoundary()
        let service = PingScopeCloudSyncService(
            historyStore: InMemoryHistoryStore(),
            hostStore: LockedSharedHostStore(state: SharedHostStoreState(hosts: [])),
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let activation = PingScopeCloudSyncActivationController(
            service: service,
            defaultsSuiteName: suiteName
        )

        let state = await activation.activatePersisted(hosts: [])
        let availabilityCallCount = await boundary.accountAvailabilityCallCount()

        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: PingScopeCloudSyncPreference.enabledKey))
        XCTAssertEqual(availabilityCallCount, 0)
        XCTAssertTrue(state.statusText.contains("repeated startup failures"))
    }

    func testSignInAccountChangeRestartsAfterStopAndResumesUpload() async throws {
        let boundary = AccountChangingCloudSyncBoundary(availability: .privateAccount)
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))

        await coordinator.setEnabled(true)
        await boundary.emitAccountChange(availability: .unavailable)

        let unavailableStatus = await coordinator.status
        let uploadWhileUnavailable = try await coordinator.upload(samples: [sample], hosts: [])
        XCTAssertEqual(unavailableStatus, .accountUnavailable)
        XCTAssertFalse(uploadWhileUnavailable)

        await boundary.emitAccountChange(availability: .privateAccount)

        let recoveredUpload = try await coordinator.upload(samples: [sample], hosts: [])
        XCTAssertTrue(recoveredUpload)
        let recoveredStatus = await coordinator.status
        let stats = await boundary.stats()
        XCTAssertEqual(recoveredStatus, .idle)
        XCTAssertEqual(stats.startCount, 2)
        XCTAssertEqual(stats.stopCount, 2)
        XCTAssertEqual(stats.uploadedRecordCount, 1)
    }

    func testAccountLossRejectsCompletionOfAnInFlightUpload() async throws {
        let boundary = GatedInFlightUploadBoundary()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))

        await coordinator.setEnabled(true)
        let upload = Task { () -> CloudSyncUploadConfirmation? in
            try? await coordinator.uploadWithConfirmation(samples: [sample], hosts: [])
        }
        await boundary.waitForUploadStart()

        await boundary.emitAccountChange(availability: .unavailable)
        await boundary.releaseUpload()
        let confirmation = await upload.value
        let status = await coordinator.status

        XCTAssertNil(confirmation)
        XCTAssertEqual(status, .accountUnavailable)
    }

    func testAccountRestartDuringRecordBuildCannotUploadIntoNewLifecycle() async throws {
        let boundary = LifecycleRecordingBoundary()
        let builder = GatedCloudSyncRecordBuilder()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary, recordBuilder: builder)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))

        await coordinator.setEnabled(true)
        let upload = Task { () -> Bool in
            (try? await coordinator.upload(samples: [sample], hosts: [])) ?? false
        }
        await builder.waitForSampleBuildStart()

        await boundary.emitAccountChange(availability: .privateAccount)
        await builder.releaseSampleBuild()

        let uploaded = await upload.value
        let uploadCount = await boundary.uploadCount()
        let status = await coordinator.status
        XCTAssertFalse(uploaded)
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(status, .idle)
    }

    func testRedundantEnableDoesNotInvalidateInFlightUpload() async throws {
        let boundary = GatedInFlightUploadBoundary()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))

        await coordinator.setEnabled(true)
        let upload = Task { () -> CloudSyncUploadConfirmation? in
            try? await coordinator.uploadWithConfirmation(samples: [sample], hosts: [])
        }
        await boundary.waitForUploadStart()

        await coordinator.setEnabled(true)
        await boundary.releaseUpload()

        let confirmation = await upload.value
        let status = await coordinator.status
        XCTAssertNotNil(confirmation)
        XCTAssertEqual(status, .idle)
    }

    func testRedundantEnableWaitsForOwnedInitialStartup() async throws {
        let boundary = GatedStartupBoundary(gateInitialStart: true)
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        let initialEnable = Task { await coordinator.setEnabled(true) }
        await boundary.waitForGatedStart()
        let completion = AsyncCompletionProbe()
        let redundantEnable = Task {
            await coordinator.setEnabled(true)
            await completion.finish()
        }

        try await Task.sleep(for: .milliseconds(25))
        let statusWhileStarting = await coordinator.status
        let completedWhileStarting = await completion.isFinished()
        XCTAssertEqual(statusWhileStarting, .checkingAccount)
        XCTAssertFalse(completedWhileStarting)

        await boundary.releaseStart()
        await initialEnable.value
        await redundantEnable.value

        let status = await coordinator.status
        let startCount = await boundary.startCount()
        let running = await boundary.isRunning()
        XCTAssertEqual(startCount, 1)
        XCTAssertTrue(running)
        XCTAssertEqual(status, .idle)
    }

    func testRedundantEnableWaitsForOwnedRecovery() async throws {
        let boundary = GatedStartupBoundary(gateInitialStart: false)
        let recoveryGate = RecoveryCallbackGate()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        await coordinator.setAccountChangeHandler {
            await recoveryGate.waitForRelease()
        }
        await coordinator.setEnabled(true)

        let accountChange = Task {
            await boundary.emitAccountChange()
        }
        await recoveryGate.waitUntilStarted()
        let completion = AsyncCompletionProbe()
        let redundantEnable = Task {
            await coordinator.setEnabled(true)
            await completion.finish()
        }

        try await Task.sleep(for: .milliseconds(25))
        let statusWhileRecovering = await coordinator.status
        let completedWhileRecovering = await completion.isFinished()
        XCTAssertEqual(statusWhileRecovering, .idle)
        XCTAssertFalse(completedWhileRecovering)

        await recoveryGate.release()
        await accountChange.value
        await redundantEnable.value

        let status = await coordinator.status
        let startCount = await boundary.startCount()
        let running = await boundary.isRunning()
        XCTAssertEqual(startCount, 2)
        XCTAssertTrue(running)
        XCTAssertEqual(status, .idle)
    }

    func testSupersededServiceDisableCannotStopNewerEnable() async throws {
        let historyStore = InMemoryHistoryStore()
        let boundary = GatedLifecycleBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncSupersededToggleTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )

        await service.setEnabled(true, hosts: [])
        await boundary.suspendHandlerClear()
        await boundary.suspendStops()

        let disabling = Task { await service.setEnabled(false, hosts: []) }
        try await waitUntil { await boundary.handlerClearHasStarted() }
        let enabling = Task { await service.setEnabled(true, hosts: []) }

        await boundary.releaseHandlerClear()
        try await waitUntil { await boundary.stopHasStarted() }
        await boundary.releaseStops()
        await disabling.value
        await enabling.value

        let status = await service.status()
        let running = await boundary.isRunning()
        XCTAssertEqual(status, .idle)
        XCTAssertTrue(running)
    }

    func testCapturedAccountChangeDuringDisableCannotRestartAfterOptOut() async throws {
        let historyStore = InMemoryHistoryStore()
        let boundary = AccountChangingCloudSyncBoundary(availability: .privateAccount)
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let gate = DisableTeardownGate()
        let suiteName = "CloudSyncCrossedDisableTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName,
            beforeDisableCoordinatorTeardown: {
                await gate.waitForRelease()
            }
        )

        await service.setEnabled(true, hosts: [])
        let disabling = Task { await service.setEnabled(false, hosts: []) }
        await gate.waitUntilStarted()

        await boundary.emitAccountChange(availability: .privateAccount)
        await gate.release()
        await disabling.value

        let status = await service.status()
        let stats = await boundary.stats()
        XCTAssertEqual(status, .off)
        XCTAssertEqual(stats.startCount, 1)
        XCTAssertEqual(stats.stopCount, 1)
    }

    func testAuthorizationTeardownDoesNotFailOpenBeforeCoordinatorDisable() async throws {
        let historyStore = InMemoryHistoryStore()
        let boundary = AccountChangingCloudSyncBoundary(availability: .privateAccount)
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let gate = DisableTeardownGate()
        let suiteName = "CloudSyncAuthorizationTeardownTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName,
            afterDisableAuthorizationTeardown: {
                await gate.waitForRelease()
            }
        )

        await service.setEnabled(true, hosts: [])
        let disabling = Task { await service.setEnabled(false, hosts: []) }
        await gate.waitUntilStarted()

        await boundary.emitAccountChange(availability: .privateAccount)
        await gate.release()
        await disabling.value

        let status = await service.status()
        let stats = await boundary.stats()
        XCTAssertEqual(status, .off)
        XCTAssertEqual(stats.startCount, 1)
        XCTAssertEqual(stats.stopCount, 1)
    }

    func testDisableDuringAccountRecoveryCallbackRemainsOff() async {
        let boundary = LifecycleRecordingBoundary()
        let recoveryGate = RecoveryCallbackGate()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        await coordinator.setAccountChangeHandler {
            await recoveryGate.waitForRelease()
        }
        await coordinator.setEnabled(true)

        let accountChange = Task {
            await boundary.emitAccountChange(availability: .privateAccount)
        }
        await recoveryGate.waitUntilStarted()
        let disabling = Task { await coordinator.setEnabled(false) }
        await disabling.value
        await recoveryGate.release()
        await accountChange.value

        let status = await coordinator.status
        XCTAssertEqual(status, .off)
    }

    func testRecordBuilderErrorRestoresIdleStatus() async {
        let boundary = LifecycleRecordingBoundary()
        let coordinator = PingScopeCloudSyncCoordinator(
            boundary: boundary,
            recordBuilder: ThrowingHostRecordBuilder()
        )
        let host = HostConfig(displayName: "Host", address: "host.example")
        await coordinator.setEnabled(true)

        do {
            _ = try await coordinator.upload(
                samples: [],
                hosts: [CloudSyncHostVersion(config: host, modifiedAt: .now)]
            )
            XCTFail("Expected record construction to fail")
        } catch {}

        let status = await coordinator.status
        XCTAssertEqual(status, .idle)
    }

    func testBoundaryUploadErrorRestoresIdleStatus() async {
        let boundary = ThrowingUploadBoundary()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: boundary)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))
        await coordinator.setEnabled(true)

        do {
            _ = try await coordinator.upload(samples: [sample], hosts: [])
            XCTFail("Expected upload to fail")
        } catch {}

        let status = await coordinator.status
        XCTAssertEqual(status, .idle)
    }

    func testAccountChangePolicyContinuesForSignInAndStopsForAccountLoss() {
        let previousUser = CKRecord.ID(recordName: "previous-user")
        let currentUser = CKRecord.ID(recordName: "current-user")
        XCTAssertEqual(
            PingScopeCKSyncAccountChangePolicy.disposition(for: .signIn(currentUser: currentUser)),
            .continueSync
        )
        XCTAssertEqual(
            PingScopeCKSyncAccountChangePolicy.disposition(for: .signOut(previousUser: previousUser)),
            .stopSync
        )
        XCTAssertEqual(
            PingScopeCKSyncAccountChangePolicy.disposition(
                for: .switchAccounts(previousUser: previousUser, currentUser: currentUser)
            ),
            .stopSync
        )
    }

    func testAccountChangeCancellationEscapesCloudKitDelegateTaskContext() async throws {
        let contextProbe = CloudKitDelegateTaskContextProbe()
        let fixture = makeRealBoundaryFixture(
            cancelSyncEngine: { _ in
                await contextProbe.record(
                    inheritedDelegateContext: CloudKitDelegateTaskContext.isActive
                )
            }
        )
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)
        fixture.host.setAvailability(.unavailable)
        let latestDelegate = await fixture.host.latestDelegate()
        let delegate = try XCTUnwrap(latestDelegate)

        await CloudKitDelegateTaskContext.$isActive.withValue(true) {
            await delegate.handleEvent(
                cloudKitAccountChangeEvent(
                    .signOut(previousUser: CKRecord.ID(recordName: "signed-out-user"))
                ),
                syncEngine: inertCloudKitSyncEngineArgument()
            )
        }
        try await waitUntil { await contextProbe.invocationCount() == 1 }

        let inheritedContexts = await contextProbe.inheritedContexts()
        XCTAssertEqual(inheritedContexts, [false])
    }

    func testAccountChangeRecoveryEscapesCloudKitDelegateTaskContext() async throws {
        let contextProbe = CloudKitDelegateTaskContextProbe()
        let fixture = makeRealBoundaryFixture(cancelSyncEngine: { _ in })
        await fixture.boundary.setAccountChangeHandler {
            await contextProbe.record(
                inheritedDelegateContext: CloudKitDelegateTaskContext.isActive
            )
        }
        _ = try await fixture.boundary.accountAvailability()
        try await fixture.boundary.start()
        let latestDelegate = await fixture.host.latestDelegate()
        let delegate = try XCTUnwrap(latestDelegate)

        await CloudKitDelegateTaskContext.$isActive.withValue(true) {
            await delegate.handleEvent(
                cloudKitAccountChangeEvent(
                    .signOut(previousUser: CKRecord.ID(recordName: "signed-out-user"))
                ),
                syncEngine: inertCloudKitSyncEngineArgument()
            )
        }
        try await waitUntil { await contextProbe.invocationCount() == 1 }

        let inheritedContexts = await contextProbe.inheritedContexts()
        XCTAssertEqual(inheritedContexts, [false])
        await fixture.boundary.stop()
    }

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

    func testAccountSwitchRetiresEngineAndClearsStaleSerializedStateBeforeRestart() async {
        let stateKey = "CloudSyncAccountSwitchTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: stateKey) }
        let fixture = makeRealBoundaryFixture(stateKey: stateKey)
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)

        await coordinator.setEnabled(true)
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: stateKey)
        await fixture.host.emitAccountChange(availability: .privateAccount)

        let events = await fixture.host.events()
        let statePresenceAtEngineCreation = await fixture.host.statePresenceAtEngineCreation()
        let activeHandleCount = await fixture.host.activeHandleCount()
        XCTAssertEqual(events.filter { if case .createEngine = $0 { true } else { false } }.count, 2)
        XCTAssertEqual(events.filter { $0 == .release }.count, 1)
        XCTAssertEqual(statePresenceAtEngineCreation, [false, false])
        XCTAssertEqual(activeHandleCount, 1)
        XCTAssertNil(UserDefaults.standard.data(forKey: stateKey))
    }

    func testAccountLossReleasesRetiredEngineDelegate() async {
        let fixture = makeRealBoundaryFixture()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)

        var strongDelegate = await fixture.host.latestDelegate()
        let weakDelegate = WeakCloudSyncDelegateReference(strongDelegate)
        XCTAssertNotNil(weakDelegate.value)
        strongDelegate = nil

        await fixture.host.emitAccountChange(availability: .unavailable)

        let status = await coordinator.status
        let activeHandleCount = await fixture.host.activeHandleCount()
        XCTAssertEqual(status, .accountUnavailable)
        XCTAssertEqual(activeHandleCount, 0)
        XCTAssertNil(weakDelegate.value)
    }

    func testRealBoundaryCoalescesConsecutiveAccountChangesDuringSuspendedRecovery() async {
        let fixture = makeRealBoundaryFixture()
        let recoveryGate = ConsecutiveAccountRecoveryGate()
        await fixture.boundary.setAccountChangeHandler {
            await recoveryGate.handleRecovery()
        }

        let firstChange = Task {
            await fixture.host.emitAccountChange(availability: .unavailable)
        }
        await recoveryGate.waitUntilFirstRecoveryStarted()

        let secondChange = Task {
            await fixture.host.emitAccountChange(availability: .privateAccount)
        }
        await secondChange.value
        await recoveryGate.releaseFirstRecovery()
        await firstChange.value

        let recoveryCount = await recoveryGate.recoveryCount()
        XCTAssertEqual(recoveryCount, 2)
    }

    func testInactiveDelegateSignInEventBehaviorallyRestartsCoordinator() async throws {
        let stateKey = "CloudSyncDelegateSignInTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: stateKey) }
        let fixture = makeRealBoundaryFixture(stateKey: stateKey)
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)

        var oldDelegate = await fixture.host.latestDelegate()
        let weakOldDelegate = WeakCloudSyncDelegateReference(oldDelegate)
        XCTAssertNotNil(weakOldDelegate.value)
        await oldDelegate?.setActive(false)
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: stateKey)

        if let oldDelegate {
            await oldDelegate.handleEvent(
                cloudKitAccountChangeEvent(
                    .signIn(currentUser: CKRecord.ID(recordName: "signed-in-user"))
                ),
                syncEngine: inertCloudKitSyncEngineArgument()
            )
        }
        oldDelegate = nil

        try await waitUntil {
            await fixture.host.engineCreationCount() == 2
        }

        let status = await coordinator.status
        let activeHandleCount = await fixture.host.activeHandleCount()
        let releaseCount = await fixture.host.releaseCount()
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(activeHandleCount, 1)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertNil(UserDefaults.standard.data(forKey: stateKey))
        XCTAssertNil(weakOldDelegate.value)
    }

    func testActiveDelegateInitialSignInKeepsTheShippingBoundaryRunning() async throws {
        let fixture = makeRealBoundaryFixture()
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)
        let latestDelegate = await fixture.host.latestDelegate()
        let delegate = try XCTUnwrap(latestDelegate)

        await delegate.handleEvent(
            cloudKitAccountChangeEvent(
                .signIn(currentUser: CKRecord.ID(recordName: "signed-in-user"))
            ),
            syncEngine: inertCloudKitSyncEngineArgument()
        )
        try await Task.sleep(for: .milliseconds(25))

        let status = await coordinator.status
        let creationCount = await fixture.host.engineCreationCount()
        let activeHandleCount = await fixture.host.activeHandleCount()
        let releaseCount = await fixture.host.releaseCount()
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(activeHandleCount, 1)
        XCTAssertEqual(releaseCount, 0)
        await coordinator.setEnabled(false)
    }

    func testDelegateSignOutEventDefersCancellationAndFullyRetiresBoundary() async throws {
        try await assertAccountLossEventFullyRetiresBoundary(
            .signOut(previousUser: CKRecord.ID(recordName: "signed-out-user"))
        )
    }

    func testDelegateAccountSwitchEventDefersCancellationAndFullyRetiresBoundary() async throws {
        try await assertAccountLossEventFullyRetiresBoundary(
            .switchAccounts(
                previousUser: CKRecord.ID(recordName: "previous-user"),
                currentUser: CKRecord.ID(recordName: "current-user")
            )
        )
    }

    func testAccountLossCancelsTheShippingBoundaryEngineOnlyOnce() async throws {
        let cancellationGate = DeferredCancellationGate()
        let fixture = makeRealBoundaryFixture(
            cancelSyncEngine: { _ in await cancellationGate.run() }
        )
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)
        fixture.host.setAvailability(.unavailable)
        let latestDelegate = await fixture.host.latestDelegate()
        let delegate = try XCTUnwrap(latestDelegate)

        let eventTask = Task {
            await delegate.handleEvent(
                cloudKitAccountChangeEvent(
                    .signOut(previousUser: CKRecord.ID(recordName: "signed-out-user"))
                ),
                syncEngine: inertCloudKitSyncEngineArgument()
            )
        }
        await cancellationGate.waitUntilStarted()
        await cancellationGate.release()
        await eventTask.value
        try await waitUntil { await fixture.host.activeHandleCount() == 0 }

        let boundaryCancellationCount = await fixture.host.events().filter { $0 == .cancel }.count
        XCTAssertEqual(
            boundaryCancellationCount,
            0,
            "The deferred account-loss cancellation already owns CKSyncEngine.cancelOperations()"
        )
    }

    private func assertAccountLossEventFullyRetiresBoundary(
        _ changeType: CKSyncEngine.Event.AccountChange.ChangeType,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let stateKey = "CloudSyncDelegateAccountLossTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: stateKey) }
        let cancellationGate = DeferredCancellationGate()
        let fixture = makeRealBoundaryFixture(
            stateKey: stateKey,
            cancelSyncEngine: { _ in await cancellationGate.run() }
        )
        let coordinator = PingScopeCloudSyncCoordinator(boundary: fixture.boundary)
        await coordinator.setEnabled(true)
        fixture.host.setAvailability(.unavailable)
        UserDefaults.standard.set(Data([0x0A, 0x0B, 0x0C]), forKey: stateKey)

        var oldDelegate = await fixture.host.latestDelegate()
        let weakOldDelegate = WeakCloudSyncDelegateReference(oldDelegate)
        let invocation = AccountChangeInvocationProbe()
        let event = cloudKitAccountChangeEvent(changeType)
        let syncEngine = inertCloudKitSyncEngineArgument()
        var eventTask: Task<Void, Never>? = Task { [oldDelegate] in
            if let oldDelegate {
                await oldDelegate.handleEvent(event, syncEngine: syncEngine)
            }
            await invocation.recordReturn()
        }

        try await waitUntil { await cancellationGate.hasStarted() }
        try await waitUntil { await invocation.hasReturned() }
        try await waitUntil { await coordinator.status == .checkingAccount }
        try await waitUntil { UserDefaults.standard.data(forKey: stateKey) == nil }

        let cancellationStarted = await cancellationGate.hasStarted()
        let eventReturnedBeforeCancellation = await invocation.hasReturned()
        let statusWhileCancellationIsSuspended = await coordinator.status
        let activeHandlesWhileCancellationIsSuspended = await fixture.host.activeHandleCount()

        await cancellationGate.release()
        await eventTask?.value
        eventTask = nil
        oldDelegate = nil

        try await waitUntil { await fixture.host.activeHandleCount() == 0 }
        let status = await coordinator.status
        let uploadAfterAccountLoss = try await coordinator.upload(samples: [], hosts: [])
        let releaseCount = await fixture.host.releaseCount()

        XCTAssertTrue(cancellationStarted, file: file, line: line)
        XCTAssertTrue(eventReturnedBeforeCancellation, file: file, line: line)
        XCTAssertEqual(statusWhileCancellationIsSuspended, .checkingAccount, file: file, line: line)
        XCTAssertEqual(activeHandlesWhileCancellationIsSuspended, 1, file: file, line: line)
        XCTAssertEqual(status, .accountUnavailable, file: file, line: line)
        XCTAssertFalse(uploadAfterAccountLoss, file: file, line: line)
        XCTAssertEqual(releaseCount, 1, file: file, line: line)
        XCTAssertNil(UserDefaults.standard.data(forKey: stateKey), file: file, line: line)
        XCTAssertNil(weakOldDelegate.value, file: file, line: line)
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

    func testRealBoundaryReturnsOnlyDelegateConfirmedRecordSaveIDs() async throws {
        let confirmed = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(1)))
        let failed = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(2)))
        let fixture = makeRealBoundaryFixture(failedRecordSaveIDs: [failed.recordID])
        try await fixture.boundary.start()

        let result = try await fixture.boundary.upload(records: [confirmed, failed], deletions: [])

        XCTAssertEqual(result.requestedRecordIDs, [confirmed.recordID, failed.recordID])
        XCTAssertEqual(result.confirmedRecordIDs, [confirmed.recordID])
        XCTAssertEqual(Set(result.failedRecordSaveErrors.keys), [failed.recordID])
        XCTAssertFalse(result.allRecordsConfirmed)
        await fixture.boundary.stop()
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

    func testCloudSyncingAppendAndWaitReturnsAfterDurabilityWhileUploadIsSuspended() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncNonblockingAppendTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(12))
        await service.setEnabled(true, hosts: [])
        await boundary.suspendSampleUploads()
        let completion = AsyncCompletionProbe()

        let append = Task {
            try await syncingStore.appendAndWait([sample])
            await completion.finish()
        }
        try await waitUntil { await boundary.sampleUploadAttemptCount() == 1 }

        let didFinishAppend = await completion.isFinished()
        XCTAssertTrue(didFinishAppend)

        await boundary.resumeSampleUploads()
        try await append.value
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }
        await service.setEnabled(false, hosts: [])
    }

    func testDrainCoalescesAppendSignalsAndKeepsOneSampleUploadInFlight() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncDrainCoalescingTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let samples = (0..<3).map { offset in
            PingResult.success(
                hostID: UUID(),
                latency: .milliseconds(Double(offset + 1)),
                timestamp: Date(timeIntervalSince1970: Double(offset + 1))
            )
        }
        await service.setEnabled(true, hosts: [])
        await boundary.suspendSampleUploads()

        let first = Task { try await syncingStore.appendAndWait([samples[0]]) }
        try await waitUntil { await boundary.sampleUploadAttemptCount() == 1 }
        let second = Task { try await syncingStore.appendAndWait([samples[1]]) }
        let third = Task { try await syncingStore.appendAndWait([samples[2]]) }
        try await waitUntil { await historyStore.unsyncedIDs().count == 3 }

        await boundary.resumeSampleUploads()
        try await first.value
        try await second.value
        try await third.value
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches.map(\.count), [1, 2])
        XCTAssertEqual(Set(batches.flatMap { $0 }), Set(samples.map(\.id)))
        let maximumConcurrentUploads = await boundary.maximumConcurrentSampleUploads()
        XCTAssertEqual(maximumConcurrentUploads, 1)
        await service.setEnabled(false, hosts: [])
    }

    func testRepeatedEnableDuringUploadDoesNotStopTheActiveDrain() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncRepeatedEnableTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(8))
        await service.setEnabled(true, hosts: [])
        await boundary.suspendSampleUploads()

        try await syncingStore.appendAndWait([sample])
        try await waitUntil { await boundary.sampleUploadAttemptCount() == 1 }
        await service.setEnabled(true, hosts: [])
        await boundary.resumeSampleUploads()
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches, [[sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testEnableRequestedDuringSuspendedDisableWinsLifecycleAndOwnsNewDrain() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncDisableReenableRaceTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        await service.setEnabled(true, hosts: [])
        await boundary.suspendStops()

        let disabling = Task { await service.setEnabled(false, hosts: []) }
        try await waitUntil { await boundary.stopAttemptCount() == 1 }
        let enabling = Task { await service.setEnabled(true, hosts: []) }
        try await Task.sleep(for: .milliseconds(25))
        await boundary.resumeStops()
        await disabling.value
        await enabling.value

        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(6))
        try await syncingStore.appendAndWait([sample])
        try await Task.sleep(for: .milliseconds(25))

        let status = await service.status()
        let unsyncedIDs = await historyStore.unsyncedIDs()
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(unsyncedIDs, [])
        await service.setEnabled(false, hosts: [])
    }

    func testOldDrainResumingUnsyncedReadAfterReenableCannotUploadItsStaleSnapshot() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncStaleReadDrainTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(11))
        await service.setEnabled(true, hosts: [])
        await historyStore.suspendNextUnsyncedRead()

        try await syncingStore.appendAndWait([sample])
        try await waitUntil { await historyStore.suspendedUnsyncedReadCount() == 1 }
        let disabling = Task { await service.setEnabled(false, hosts: []) }
        try await waitUntil { await boundary.stopAttemptCount() == 1 }
        let enabling = Task { await service.setEnabled(true, hosts: []) }
        try await waitUntil { await boundary.sampleUploadAttemptCount() == 1 }

        await historyStore.resumeUnsyncedReads()
        await disabling.value
        await enabling.value
        try await Task.sleep(for: .milliseconds(25))

        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches, [[sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testLocalAcknowledgementRetriesWithoutReuploadingConfirmedSampleIDs() async throws {
        let historyStore = OutboxHistoryStore(markFailures: 1)
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncAcknowledgementRetryTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(9))
        await service.setEnabled(true, hosts: [])

        try await syncingStore.appendAndWait([sample])
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }

        let markAttempts = await historyStore.markAttemptCount()
        let sampleBatches = await boundary.sampleUploadBatches()
        XCTAssertEqual(markAttempts, 2)
        XCTAssertEqual(sampleBatches, [[sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testPartialRecordSaveAcknowledgesOnlyCloudKitConfirmedSampleIDs() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncPartialSaveTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let confirmed = PingResult.success(hostID: UUID(), latency: .milliseconds(7))
        let failed = PingResult.success(hostID: UUID(), latency: .milliseconds(8))
        await service.setEnabled(true, hosts: [])
        await boundary.failSampleSaves(ids: [failed.id])

        try await syncingStore.appendAndWait([confirmed, failed])
        try await waitUntil { await boundary.sampleUploadAttemptCount() == 1 }
        try await Task.sleep(for: .milliseconds(25))

        let unsyncedIDs = await historyStore.unsyncedIDs()
        let markAttempts = await historyStore.markAttemptCount()
        XCTAssertEqual(unsyncedIDs, [failed.id])
        XCTAssertEqual(markAttempts, 1)
        await service.setEnabled(false, hosts: [])
    }

    func testRemoteHostBatchIsSanitizedIndexedAndCappedAt64() async throws {
        let fixture = makeServiceFixture(hosts: [])
        defer { fixture.cleanup() }
        let invalid = HostConfig(displayName: "   ", address: "invalid.example")
        let validHosts = (0..<65).map { index in
            HostConfig(
                displayName: "  Remote \(index)  ",
                address: "  host-\(index).example  ",
                interval: .milliseconds(1),
                timeout: .seconds(120)
            )
        }
        let records = try ([invalid] + validHosts).map {
            try MonitoredHostRecordMapper.record(from: $0, modifiedAt: .now)
        }

        await fixture.service.applyRemoteChanges(records: records)

        let applied = try XCTUnwrap(fixture.hostStore.load().state?.hosts)
        XCTAssertEqual(applied.count, 64)
        XCTAssertEqual(Set(applied.map(\.id)), Set(validHosts.prefix(64).map(\.id)))
        XCTAssertTrue(applied.allSatisfy { !$0.displayName.hasPrefix(" ") && !$0.displayName.hasSuffix(" ") })
        XCTAssertTrue(applied.allSatisfy { $0.interval == .milliseconds(250) && $0.timeout == .seconds(60) })
        XCTAssertEqual(fixture.hostStore.saveCount(), 1)
    }

    func testRemoteVersionMetadataAdvancesOnlyAfterHostStoreSaveSucceeds() async throws {
        let hostID = UUID()
        let local = HostConfig(id: hostID, displayName: "Local", address: "local.example")
        let remote = HostConfig(id: hostID, displayName: "Remote", address: "remote.example")
        let hostStore = FailingOnceSharedHostStore(state: SharedHostStoreState(hosts: [local]))
        let boundary = RecordingCloudSyncBoundary(failingUploadAttempts: [])
        let suiteName = "CloudSyncRemoteSaveRetryTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: InMemoryHistoryStore(),
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let record = try MonitoredHostRecordMapper.record(
            from: remote,
            modifiedAt: Date(timeIntervalSince1970: 10_000)
        )

        await service.applyRemoteChanges(records: [record])
        XCTAssertEqual(hostStore.load().state?.hosts, [local])

        await service.applyRemoteChanges(records: [record])
        XCTAssertEqual(hostStore.load().state?.hosts, [remote])
        XCTAssertEqual(hostStore.saveAttemptCount(), 2)
    }

    func testRemoteHostVersionsPersistOnceForTheWholeBatch() async throws {
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let boundary = RecordingCloudSyncBoundary(failingUploadAttempts: [])
        let persistenceCounter = LockedCounter()
        let suiteName = "CloudSyncRemoteBatchPersistenceTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: InMemoryHistoryStore(),
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName,
            registryPersistenceObserver: { persistenceCounter.increment() }
        )
        let records = try (0..<3).map { index in
            try MonitoredHostRecordMapper.record(
                from: HostConfig(displayName: "Remote \(index)", address: "host-\(index).example"),
                modifiedAt: Date(timeIntervalSince1970: Double(1_000 + index))
            )
        }

        await service.applyRemoteChanges(records: records)

        XCTAssertEqual(persistenceCounter.value(), 1)
        XCTAssertEqual(hostStore.saveCount(), 1)
    }

    func testDelegateStateReportsMixedSaveConfirmationAndCompactsOutcomeCaches() async {
        let state = PingScopeCKSyncEngineDelegateState()
        let confirmed = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(1)))
        let failed = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(2)))
        await state.setActive(true)
        await state.prepare(records: [confirmed, failed], deletions: [])
        await state.stage([confirmed, failed])
        await state.recordSaveResults(
            savedRecordIDs: [confirmed.recordID],
            failures: [failed.recordID: CKError(.networkFailure)]
        )
        await state.remove([confirmed.recordID])

        let result = await state.consumeSaveConfirmation(for: [confirmed.recordID, failed.recordID])
        let failedStagedRecord = await state.record(for: failed.recordID)
        let counts = await state.cacheCounts()

        XCTAssertEqual(result.confirmedRecordIDs, [confirmed.recordID])
        XCTAssertEqual(Set(result.failedRecordSaveErrors.keys), [failed.recordID])
        XCTAssertFalse(result.allRecordsConfirmed)
        XCTAssertNil(failedStagedRecord)
        XCTAssertEqual(counts.stagedRecords, 0)
        XCTAssertEqual(counts.awaitingRecordSaves, 0)
        XCTAssertEqual(counts.confirmedRecordSaves, 0)
        XCTAssertEqual(counts.failedRecordSaves, 0)
    }

    func testDefinitiveBoundaryStopClearsTerminalDelegateCaches() async {
        let state = PingScopeCKSyncEngineDelegateState()
        let record = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(1)))
        let deletionID = CKRecord.ID(recordName: UUID().uuidString, zoneID: PingScopeCloudKitModel.zoneID)
        await state.setActive(true)
        await state.prepare(records: [record], deletions: [deletionID])
        await state.stage([record])
        await state.recordSaveResults(
            savedRecordIDs: [],
            failures: [record.recordID: CKError(.networkFailure)]
        )
        await state.recordDeleteFailures([deletionID: CKError(.networkFailure)])

        _ = await state.deactivateAndAwaitDeferredCancellation()

        let counts = await state.cacheCounts()
        XCTAssertEqual(counts.stagedRecords, 0)
        XCTAssertEqual(counts.awaitingRecordSaves, 0)
        XCTAssertEqual(counts.confirmedRecordSaves, 0)
        XCTAssertEqual(counts.failedRecordSaves, 0)
        XCTAssertEqual(counts.failedDeletions, 0)
    }

    func testDefinitiveBoundaryStopAwaitsAndReleasesDeferredCancellationLifetime() async {
        let state = PingScopeCKSyncEngineDelegateState()
        let gate = DeferredCancellationGate()
        var lifetimeToken: DeferredCancellationLifetimeToken? = .init()
        let weakLifetimeToken = WeakDeferredCancellationLifetimeToken(lifetimeToken)
        await state.setActive(true)

        await state.scheduleCancellation(operation: { [lifetimeToken] in
            await gate.run()
            _ = lifetimeToken
        })
        lifetimeToken = nil
        await gate.waitUntilStarted()
        XCTAssertNotNil(weakLifetimeToken.value)

        let definitiveStop = Task {
            await state.deactivateAndAwaitDeferredCancellation()
        }
        await Task.yield()
        XCTAssertNotNil(weakLifetimeToken.value)

        await gate.release()
        _ = await definitiveStop.value

        XCTAssertNil(weakLifetimeToken.value)
    }

    func testStaleUploadPreparationAfterDefinitiveStopCannotRepopulateDelegateCaches() async {
        let state = PingScopeCKSyncEngineDelegateState()
        let record = PingSampleRecordMapper.record(from: .success(hostID: UUID(), latency: .milliseconds(1)))
        await state.setActive(true)

        let staleUploadObservedActiveState = await state.isActive()
        _ = await state.deactivateAndAwaitDeferredCancellation()
        XCTAssertTrue(staleUploadObservedActiveState)
        await state.prepare(records: [record], deletions: [])

        let counts = await state.cacheCounts()
        XCTAssertEqual(counts.stagedRecords, 0)
        XCTAssertEqual(counts.awaitingRecordSaves, 0)
        XCTAssertEqual(counts.confirmedRecordSaves, 0)
        XCTAssertEqual(counts.failedRecordSaves, 0)
        XCTAssertEqual(counts.failedDeletions, 0)
    }

    func testAcknowledgementExhaustionRetainsConfirmationAndLaterSignalDoesNotReuploadIt() async throws {
        let historyStore = OutboxHistoryStore(markFailures: 3)
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncAcknowledgementExhaustionTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let confirmed = PingResult.success(hostID: UUID(), latency: .milliseconds(4))
        let later = PingResult.success(hostID: UUID(), latency: .milliseconds(5))
        await service.setEnabled(true, hosts: [])

        try await syncingStore.appendAndWait([confirmed])
        try await waitUntil { await historyStore.markAttemptCount() == 3 }
        try await Task.sleep(for: .milliseconds(30))
        let exhaustedUnsyncedIDs = await historyStore.unsyncedIDs()
        let exhaustedBatches = await boundary.sampleUploadBatches()
        XCTAssertEqual(exhaustedUnsyncedIDs, [confirmed.id])
        XCTAssertEqual(exhaustedBatches, [[confirmed.id]])

        try await syncingStore.appendAndWait([later])
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }
        let batches = await boundary.sampleUploadBatches()
        let markAttempts = await historyStore.markAttemptCount()
        XCTAssertEqual(batches, [[confirmed.id], [later.id]])
        XCTAssertEqual(markAttempts, 5)
        await service.setEnabled(false, hosts: [])
    }

    func testOldAcknowledgementReturningAfterReenableCannotClearNewLifecycleConfirmation() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncStaleAcknowledgementTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let oldSample = PingResult.success(hostID: UUID(), latency: .milliseconds(21))
        let newSample = PingResult.success(hostID: UUID(), latency: .milliseconds(22))
        let laterSample = PingResult.success(hostID: UUID(), latency: .milliseconds(23))
        await service.setEnabled(true, hosts: [])
        await historyStore.suspendNextSuccessfulMarkAfterMutation()

        try await syncingStore.appendAndWait([oldSample])
        try await waitUntil { await historyStore.suspendedSuccessfulMarkCount() == 1 }
        try await historyStore.appendAndWait([newSample])
        await historyStore.failNextMarkAttempts(3)

        let disabling = Task { await service.setEnabled(false, hosts: []) }
        try await waitUntil { await boundary.stopAttemptCount() == 1 }
        let enabling = Task { await service.setEnabled(true, hosts: []) }
        try await waitUntil { await historyStore.markAttemptCount() == 4 }
        await enabling.value

        await historyStore.resumeSuccessfulMarks()
        await disabling.value
        try await syncingStore.appendAndWait([laterSample])
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches, [[oldSample.id], [newSample.id], [laterSample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testDisableCancelsAcknowledgementBackoffAndReenableStartsFreshUpload() async throws {
        let historyStore = OutboxHistoryStore(markFailures: 1, markFailureDelay: .seconds(5))
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncAcknowledgementCancellationTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let sample = PingResult.success(hostID: UUID(), latency: .milliseconds(3))
        await service.setEnabled(true, hosts: [])

        try await syncingStore.appendAndWait([sample])
        try await waitUntil { await historyStore.markAttemptCount() == 1 }
        await service.setEnabled(false, hosts: [])

        let stoppedUnsyncedIDs = await historyStore.unsyncedIDs()
        let stoppedMarkAttempts = await historyStore.markAttemptCount()
        XCTAssertEqual(stoppedUnsyncedIDs, [sample.id])
        XCTAssertEqual(stoppedMarkAttempts, 1)
        await service.setEnabled(true, hosts: [])
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }
        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches, [[sample.id], [sample.id]])
        await service.setEnabled(false, hosts: [])
    }

    func testDrainSplits301DurableRowsInto300And1RecordUploads() async throws {
        let historyStore = OutboxHistoryStore()
        let boundary = GatedCloudSyncBoundary()
        let hostStore = LockedSharedHostStore(state: SharedHostStoreState(hosts: []))
        let suiteName = "CloudSyncBatchBoundTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PingScopeCloudSyncService(
            historyStore: historyStore,
            hostStore: hostStore,
            boundary: boundary,
            recordBuilder: DefaultCloudSyncRecordBuilder(),
            registrySuiteName: suiteName
        )
        let syncingStore = CloudSyncingHistoryStore(destination: historyStore, service: service)
        let samples = (0..<301).map { offset in
            PingResult.success(
                hostID: UUID(),
                latency: .milliseconds(Double(offset + 1)),
                timestamp: Date(timeIntervalSince1970: Double(offset + 1))
            )
        }
        await service.setEnabled(true, hosts: [])

        try await syncingStore.appendAndWait(samples)
        try await waitUntil { await historyStore.unsyncedIDs().isEmpty }

        let batches = await boundary.sampleUploadBatches()
        XCTAssertEqual(batches.map(\.count), [300, 1])
        XCTAssertEqual(Set(batches.flatMap { $0 }), Set(samples.map(\.id)))
        await service.setEnabled(false, hosts: [])
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

    func testAcceptedRemoteHostColorPublishesExactPersistedHostState() async throws {
        let host = HostConfig(displayName: "Host", address: "old.example")
        let peer = HostConfig(displayName: "Peer", address: "peer.example")
        var remote = host
        remote.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        let fixture = makeServiceFixture(hosts: [host, peer])
        let recorder = AcceptedHostStateRecorder()
        defer { fixture.cleanup() }
        await fixture.service.setEnabled(true, hosts: [host, peer])
        await fixture.boundary.resetUploads()
        await fixture.service.setAcceptedHostStateHandler { state in
            await recorder.record(state)
        }
        let remoteRecord = try MonitoredHostRecordMapper.record(
            from: remote,
            modifiedAt: Date().addingTimeInterval(1_000)
        )

        await fixture.service.applyRemoteChanges(records: [remoteRecord])

        let persistedState = try XCTUnwrap(fixture.hostStore.load().state)
        let acceptedStates = await recorder.values()
        XCTAssertEqual(persistedState.hosts, [remote, peer])
        XCTAssertEqual(
            acceptedStates,
            [persistedState],
            "The live app boundary must receive the exact accepted post-save host state."
        )

        var unrelatedPeerEdit = peer
        unrelatedPeerEdit.notifications = .muted
        let locallyEditedState = SharedHostStoreState(hosts: [remote, unrelatedPeerEdit])
        try fixture.hostStore.save(locallyEditedState)
        await fixture.service.uploadHosts(
            locallyEditedState.hosts,
            modifiedAt: Date().addingTimeInterval(2_000)
        )

        let uploadedVersions = await fixture.boundary.uploadedHostVersions()
        XCTAssertEqual(uploadedVersions.map(\.config), [unrelatedPeerEdit])
        XCTAssertEqual(fixture.hostStore.load().state?.hosts.first?.displayColor, remote.displayColor)
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

    func testPendingHostDeletionsAreUploadedInOneBatch() async throws {
        let hosts = (0..<4).map {
            HostConfig(displayName: "Deleted \($0)", address: "deleted-\($0).example")
        }
        let fixture = makeServiceFixture(hosts: hosts)
        defer { fixture.cleanup() }
        try fixture.hostStore.save(SharedHostStoreState(hosts: []))

        for host in hosts {
            await fixture.service.deleteHost(id: host.id)
        }
        await fixture.service.setEnabled(true, hosts: [])

        let batches = await fixture.boundary.attemptedDeletionBatches()
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(Set(batches[0]), Set(hosts.map(\.id)))
    }
}

private struct ThrowingCloudKitContainerProvider: CloudKitContainerProviding {
    func defaultContainer(for identifier: String) throws -> CKContainer {
        throw CloudSyncBoundaryError.missingContainerEntitlement("iCloud.com.example.Missing")
    }
}

private actor RecordingActivationService: PingScopeCloudSyncControlling {
    private var currentStatus: PingScopeCloudSyncStatus
    private var enableCalls = 0
    private var disableCalls = 0

    init(status: PingScopeCloudSyncStatus) {
        self.currentStatus = status
    }

    func setEnabled(_ enabled: Bool, hosts: [HostConfig]) async {
        if enabled {
            enableCalls += 1
        } else {
            disableCalls += 1
        }
    }

    func status() async -> PingScopeCloudSyncStatus { currentStatus }
    func enableCallCount() -> Int { enableCalls }
    func disableCallCount() -> Int { disableCalls }
}

private actor GatedActivationService: PingScopeCloudSyncControlling {
    private var currentStatus: PingScopeCloudSyncStatus = .checkingAccount
    private var enableStarted = false
    private var enableWaiters: [CheckedContinuation<Void, Never>] = []
    private var enableContinuation: CheckedContinuation<Void, Never>?

    func setEnabled(_ enabled: Bool, hosts: [HostConfig]) async {
        guard enabled else {
            currentStatus = .off
            return
        }
        enableStarted = true
        for waiter in enableWaiters { waiter.resume() }
        enableWaiters.removeAll()
        await withCheckedContinuation { continuation in
            enableContinuation = continuation
        }
    }

    func status() async -> PingScopeCloudSyncStatus { currentStatus }

    func waitForEnableCall() async {
        guard !enableStarted else { return }
        await withCheckedContinuation { enableWaiters.append($0) }
    }

    func releaseEnable(with status: PingScopeCloudSyncStatus) {
        currentStatus = status
        enableContinuation?.resume()
        enableContinuation = nil
    }
}

private enum ThrowingAvailabilityCloudSyncBoundaryError: Error {
    case missingContainerEntitlement
}

private actor ThrowingAvailabilityCloudSyncBoundary: CloudSyncEngineBoundary {
    private var starts = 0
    private var availabilityCalls = 0

    func accountAvailability() async throws -> CloudSyncAccountAvailability {
        availabilityCalls += 1
        throw ThrowingAvailabilityCloudSyncBoundaryError.missingContainerEntitlement
    }

    func start() async throws {
        starts += 1
    }

    func stop() async {}

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        CloudSyncUploadConfirmation(confirming: records)
    }

    func startCallCount() -> Int { starts }
    func accountAvailabilityCallCount() -> Int { availabilityCalls }
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
    private var saves = 0

    init(state: SharedHostStoreState) {
        self.state = state
    }

    func load() -> SharedHostStoreLoadResult {
        lock.withLock { SharedHostStoreLoadResult(state: state, source: .shared) }
    }

    func save(_ state: SharedHostStoreState) throws {
        lock.withLock {
            self.state = state
            saves += 1
        }
    }

    func saveCount() -> Int { lock.withLock { saves } }
}

private actor AcceptedHostStateRecorder {
    private var states: [SharedHostStoreState] = []

    func record(_ state: SharedHostStoreState) {
        states.append(state)
    }

    func values() -> [SharedHostStoreState] {
        states
    }
}

private enum FailingSharedHostStoreError: Error {
    case forcedSaveFailure
}

private final class FailingOnceSharedHostStore: SharedHostStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SharedHostStoreState
    private var saveAttempts = 0

    init(state: SharedHostStoreState) {
        self.state = state
    }

    func load() -> SharedHostStoreLoadResult {
        lock.withLock { SharedHostStoreLoadResult(state: state, source: .shared) }
    }

    func save(_ state: SharedHostStoreState) throws {
        try lock.withLock {
            saveAttempts += 1
            guard saveAttempts > 1 else { throw FailingSharedHostStoreError.forcedSaveFailure }
            self.state = state
        }
    }

    func saveAttemptCount() -> Int { lock.withLock { saveAttempts } }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    func value() -> Int { lock.withLock { count } }
}

private actor AsyncCompletionProbe {
    private var finished = false

    func finish() { finished = true }
    func isFinished() -> Bool { finished }
}

private enum OutboxHistoryStoreError: Error {
    case forcedMarkFailure
}

private actor OutboxHistoryStore: PingHistoryStore {
    private var samplesByID: [UUID: PingResult] = [:]
    private var unsyncedOrder: [UUID] = []
    private var remainingMarkFailures: Int
    private let markFailureDelay: Duration?
    private var markAttempts = 0
    private var shouldSuspendNextUnsyncedRead = false
    private var suspendedUnsyncedReads: [CheckedContinuation<Void, Never>] = []
    private var totalSuspendedUnsyncedReads = 0
    private var shouldSuspendNextSuccessfulMark = false
    private var suspendedSuccessfulMarks: [CheckedContinuation<Void, Never>] = []
    private var totalSuspendedSuccessfulMarks = 0

    init(markFailures: Int = 0, markFailureDelay: Duration? = nil) {
        self.remainingMarkFailures = markFailures
        self.markFailureDelay = markFailureDelay
    }

    func append(_ result: PingResult) async { appendLocally([result]) }
    func append(_ results: [PingResult]) async { appendLocally(results) }
    func appendAndWait(_ results: [PingResult]) async throws { appendLocally(results) }

    func unsyncedSamples(limit: Int) async throws -> [PingResult] {
        let snapshot = unsyncedOrder.prefix(limit).compactMap { samplesByID[$0] }
        if shouldSuspendNextUnsyncedRead {
            shouldSuspendNextUnsyncedRead = false
            totalSuspendedUnsyncedReads += 1
            await withCheckedContinuation { continuation in
                suspendedUnsyncedReads.append(continuation)
            }
        }
        return snapshot
    }

    func markSamplesSynced(ids: [UUID]) async throws {
        markAttempts += 1
        if remainingMarkFailures > 0 {
            remainingMarkFailures -= 1
            if let markFailureDelay {
                try await Task.sleep(for: markFailureDelay)
            }
            throw OutboxHistoryStoreError.forcedMarkFailure
        }
        let confirmed = Set(ids)
        unsyncedOrder.removeAll { confirmed.contains($0) }
        if shouldSuspendNextSuccessfulMark {
            shouldSuspendNextSuccessfulMark = false
            totalSuspendedSuccessfulMarks += 1
            await withCheckedContinuation { continuation in
                suspendedSuccessfulMarks.append(continuation)
            }
        }
    }

    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func unsyncedIDs() -> [UUID] { unsyncedOrder }
    func markAttemptCount() -> Int { markAttempts }
    func suspendedUnsyncedReadCount() -> Int { totalSuspendedUnsyncedReads }
    func suspendedSuccessfulMarkCount() -> Int { totalSuspendedSuccessfulMarks }

    func suspendNextUnsyncedRead() { shouldSuspendNextUnsyncedRead = true }
    func suspendNextSuccessfulMarkAfterMutation() { shouldSuspendNextSuccessfulMark = true }
    func failNextMarkAttempts(_ count: Int) { remainingMarkFailures = count }

    func resumeUnsyncedReads() {
        let continuations = suspendedUnsyncedReads
        suspendedUnsyncedReads.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func resumeSuccessfulMarks() {
        let continuations = suspendedSuccessfulMarks
        suspendedSuccessfulMarks.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    private func appendLocally(_ results: [PingResult]) {
        for result in results {
            if samplesByID.updateValue(result, forKey: result.id) == nil {
                unsyncedOrder.append(result.id)
            }
        }
    }
}

private actor GatedCloudSyncBoundary: CloudSyncEngineBoundary {
    private var shouldSuspendSampleUploads = false
    private var suspendedUploads: [CheckedContinuation<Void, Never>] = []
    private var sampleAttempts = 0
    private var sampleBatches: [[UUID]] = []
    private var activeSampleUploads = 0
    private var maximumActiveSampleUploads = 0
    private var failedSampleSaveIDs: Set<UUID> = []
    private var shouldSuspendStops = false
    private var suspendedStops: [CheckedContinuation<Void, Never>] = []
    private var stopAttempts = 0

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }
    func start() async throws {}
    func stop() async {
        stopAttempts += 1
        resumeSampleUploads()
        if shouldSuspendStops {
            await withCheckedContinuation { continuation in
                suspendedStops.append(continuation)
            }
        }
    }

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        let sampleIDs = records
            .filter { $0.recordType == PingScopeCloudKitModel.RecordType.pingSample }
            .compactMap { UUID(uuidString: $0.recordID.recordName) }
        guard !sampleIDs.isEmpty else { return CloudSyncUploadConfirmation(confirming: records) }
        sampleAttempts += 1
        activeSampleUploads += 1
        maximumActiveSampleUploads = max(maximumActiveSampleUploads, activeSampleUploads)
        if shouldSuspendSampleUploads {
            await withCheckedContinuation { continuation in
                suspendedUploads.append(continuation)
            }
        }
        sampleBatches.append(sampleIDs)
        activeSampleUploads -= 1
        let failedRecordIDs = Set(records.compactMap { record -> CKRecord.ID? in
            guard let id = UUID(uuidString: record.recordID.recordName),
                  failedSampleSaveIDs.contains(id) else { return nil }
            return record.recordID
        })
        let requestedRecordIDs = Set(records.map(\.recordID))
        return CloudSyncUploadConfirmation(
            requestedRecordIDs: requestedRecordIDs,
            confirmedRecordIDs: requestedRecordIDs.subtracting(failedRecordIDs),
            failedRecordSaveErrors: Dictionary(uniqueKeysWithValues: failedRecordIDs.map {
                ($0, CKError(.networkFailure))
            })
        )
    }

    func suspendSampleUploads() { shouldSuspendSampleUploads = true }
    func failSampleSaves(ids: Set<UUID>) { failedSampleSaveIDs = ids }
    func suspendStops() { shouldSuspendStops = true }

    func resumeSampleUploads() {
        shouldSuspendSampleUploads = false
        let continuations = suspendedUploads
        suspendedUploads.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func resumeStops() {
        shouldSuspendStops = false
        let continuations = suspendedStops
        suspendedStops.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func sampleUploadAttemptCount() -> Int { sampleAttempts }
    func sampleUploadBatches() -> [[UUID]] { sampleBatches }
    func maximumConcurrentSampleUploads() -> Int { maximumActiveSampleUploads }
    func stopAttemptCount() -> Int { stopAttempts }
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        guard clock.now < deadline else {
            XCTFail("Timed out waiting for asynchronous condition")
            return
        }
        try await Task.sleep(for: .milliseconds(5))
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

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
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
        return CloudSyncUploadConfirmation(confirming: records)
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

    func attemptedDeletionBatches() -> [[UUID]] {
        attemptedDeletions.map { batch in
            batch.compactMap { UUID(uuidString: $0.recordName) }
        }.filter { !$0.isEmpty }
    }
}

private enum FakeCloudSyncBoundaryError: Error {
    case teardownFailed
}

private enum AccountChangingCloudSyncBoundaryError: Error {
    case inactive
}

private final class WeakCloudSyncDelegateReference {
    weak var value: PingScopeCKSyncEngineDelegate?

    init(_ value: PingScopeCKSyncEngineDelegate?) {
        self.value = value
    }
}

private final class DeferredCancellationLifetimeToken: @unchecked Sendable {}

private final class WeakDeferredCancellationLifetimeToken {
    weak var value: DeferredCancellationLifetimeToken?

    init(_ value: DeferredCancellationLifetimeToken?) {
        self.value = value
    }
}

private actor AccountChangeInvocationProbe {
    private var returned = false

    func recordReturn() {
        returned = true
    }

    func hasReturned() -> Bool {
        returned
    }
}

private actor ConsecutiveAccountRecoveryGate {
    private var count = 0
    private var firstRecoveryStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var firstRecoveryReleaseContinuation: CheckedContinuation<Void, Never>?

    func handleRecovery() async {
        count += 1
        guard count == 1 else { return }
        let continuations = firstRecoveryStartedContinuations
        firstRecoveryStartedContinuations.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstRecoveryReleaseContinuation = continuation
        }
    }

    func waitUntilFirstRecoveryStarted() async {
        guard count == 0 else { return }
        await withCheckedContinuation { continuation in
            firstRecoveryStartedContinuations.append(continuation)
        }
    }

    func releaseFirstRecovery() {
        firstRecoveryReleaseContinuation?.resume()
        firstRecoveryReleaseContinuation = nil
    }

    func recoveryCount() -> Int { count }
}

private final class InertCloudKitSyncEngineStorage: @unchecked Sendable {}

private func inertCloudKitSyncEngineArgument() -> CKSyncEngine {
    // CKSyncEngine initialization requires a CloudKit-entitled test process.
    // Account-change handling only forwards this reference to the injected
    // cancellation edge, so an inert class reference is sufficient in SwiftPM.
    unsafeBitCast(InertCloudKitSyncEngineStorage(), to: CKSyncEngine.self)
}

private func cloudKitAccountChangeEvent(
    _ changeType: CKSyncEngine.Event.AccountChange.ChangeType
) -> CKSyncEngine.Event {
    // Apple exposes AccountChange.changeType but no public payload initializer.
    // Fail loudly if a future SDK changes its current single-field layout.
    precondition(
        MemoryLayout.size(ofValue: changeType)
            == MemoryLayout<CKSyncEngine.Event.AccountChange>.size
            && MemoryLayout.stride(ofValue: changeType)
            == MemoryLayout<CKSyncEngine.Event.AccountChange>.stride
            && MemoryLayout.alignment(ofValue: changeType)
            == MemoryLayout<CKSyncEngine.Event.AccountChange>.alignment
    )
    return .accountChange(
        unsafeBitCast(changeType, to: CKSyncEngine.Event.AccountChange.self)
    )
}

private enum CloudKitDelegateTaskContext {
    @TaskLocal static var isActive = false
}

private actor CloudKitDelegateTaskContextProbe {
    private var inheritedDelegateContexts: [Bool] = []

    func record(inheritedDelegateContext: Bool) {
        inheritedDelegateContexts.append(inheritedDelegateContext)
    }

    func invocationCount() -> Int { inheritedDelegateContexts.count }
    func inheritedContexts() -> [Bool] { inheritedDelegateContexts }
}

private actor DeferredCancellationGate {
    private var isStarted = false
    private var isReleased = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func run() async {
        isStarted = true
        let continuations = startedContinuations
        startedContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func hasStarted() -> Bool {
        isStarted
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor AccountChangingCloudSyncBoundary: CloudSyncEngineBoundary {
    private var availability: CloudSyncAccountAvailability
    private var isActive = false
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var startCount = 0
    private var stopCount = 0
    private var uploadedRecordCount = 0

    init(availability: CloudSyncAccountAvailability) {
        self.availability = availability
    }

    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) {
        accountChangeHandler = handler
    }

    func emitAccountChange(availability: CloudSyncAccountAvailability) async {
        self.availability = availability
        isActive = false
        await accountChangeHandler?()
    }

    func accountAvailability() async -> CloudSyncAccountAvailability {
        availability
    }

    func start() async throws {
        startCount += 1
        isActive = true
    }

    func stop() async {
        stopCount += 1
        isActive = false
    }

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        guard isActive else { throw AccountChangingCloudSyncBoundaryError.inactive }
        uploadedRecordCount += records.count
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func stats() -> (startCount: Int, stopCount: Int, uploadedRecordCount: Int) {
        (startCount, stopCount, uploadedRecordCount)
    }
}

private struct RealBoundaryFixture {
    let boundary: CKSyncEngineBoundary
    let host: RecordingCloudKitEngineHost
    let subscriptionID: CKSubscription.ID
    let stateKey: String
}

private func makeRealBoundaryFixture(
    deleteError: CKError? = nil,
    failedRecordSaveIDs: Set<CKRecord.ID> = [],
    stateKey: String = "CloudSyncBoundaryTests-\(UUID().uuidString)",
    cancelSyncEngine: @escaping @Sendable (CKSyncEngine) async -> Void = {
        await $0.cancelOperations()
    }
) -> RealBoundaryFixture {
    let subscriptionID = "PingScope.CloudSync.PrivateDatabase"
    let host = RecordingCloudKitEngineHost(
        deleteError: deleteError,
        failedRecordSaveIDs: failedRecordSaveIDs,
        serializedStateExists: {
            UserDefaults.standard.data(forKey: stateKey) != nil
        }
    )
    let boundary = CKSyncEngineBoundary(
        engineHost: host,
        stateKey: stateKey,
        subscriptionID: subscriptionID,
        cancelSyncEngine: cancelSyncEngine
    )
    return RealBoundaryFixture(
        boundary: boundary,
        host: host,
        subscriptionID: subscriptionID,
        stateKey: stateKey
    )
}

private func assertBoundaryIsInactive(
    _ boundary: CKSyncEngineBoundary,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await boundary.upload(records: [], deletions: [])
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
    private let failedRecordSaveIDs: Set<CKRecord.ID>
    private let serializedStateExists: @Sendable () -> Bool
    private let lock = NSLock()
    private var recordedEvents: [RecordingCloudKitEngineHostEvent] = []
    private var activeHandles: Set<CloudKitEngineHandle> = []
    private var delegates: [CloudKitEngineHandle: PingScopeCKSyncEngineDelegate] = [:]
    private var pendingSaveIDs: [CloudKitEngineHandle: [CKRecord.ID]] = [:]
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var availability: CloudSyncAccountAvailability = .privateAccount
    private var recordedStatePresenceAtEngineCreation: [Bool] = []

    init(
        deleteError: CKError?,
        failedRecordSaveIDs: Set<CKRecord.ID> = [],
        serializedStateExists: @escaping @Sendable () -> Bool = { false }
    ) {
        self.deleteError = deleteError
        self.failedRecordSaveIDs = failedRecordSaveIDs
        self.serializedStateExists = serializedStateExists
    }

    func prepareResources() {
        lock.withLock {
            recordedEvents.append(.prepareResources)
        }
    }

    func accountAvailability() async -> CloudSyncAccountAvailability {
        lock.withLock { availability }
    }

    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) {
        lock.withLock { accountChangeHandler = handler }
    }

    func emitAccountChange(availability: CloudSyncAccountAvailability) async {
        let handler = lock.withLock {
            self.availability = availability
            return accountChangeHandler
        }
        await handler?()
    }

    func setAvailability(_ availability: CloudSyncAccountAvailability) {
        lock.withLock { self.availability = availability }
    }

    func createEngine(
        stateSerialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: CKSubscription.ID
    ) -> CloudKitEngineHandle {
        let handle = CloudKitEngineHandle()
        lock.withLock {
            activeHandles.insert(handle)
            delegates[handle] = delegate as? PingScopeCKSyncEngineDelegate
            recordedStatePresenceAtEngineCreation.append(serializedStateExists())
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
            pendingSaveIDs[handle, default: []].append(contentsOf: changes.compactMap { change in
                guard case let .saveRecord(id) = change else { return nil }
                return id
            })
            recordedEvents.append(.addRecordChanges)
        }
    }

    func sendChanges(on handle: CloudKitEngineHandle) async throws {
        let outcome = lock.withLock { () -> (PingScopeCKSyncEngineDelegate?, [CKRecord.ID]) in
            guard activeHandles.contains(handle) else { return (nil, []) }
            recordedEvents.append(.sendChanges)
            let ids = pendingSaveIDs.removeValue(forKey: handle) ?? []
            return (delegates[handle], ids)
        }
        if let delegate = outcome.0, !outcome.1.isEmpty {
            let failedIDs = outcome.1.filter(failedRecordSaveIDs.contains)
            await delegate.recordSaveResultsForTesting(
                savedRecordIDs: outcome.1.filter { !failedRecordSaveIDs.contains($0) },
                failures: Dictionary(uniqueKeysWithValues: failedIDs.map {
                    ($0, CKError(.networkFailure))
                })
            )
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
            delegates[handle] = nil
            pendingSaveIDs[handle] = nil
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

    func activeHandleCount() async -> Int {
        lock.withLock { activeHandles.count }
    }

    func engineCreationCount() async -> Int {
        lock.withLock {
            recordedEvents.reduce(into: 0) { count, event in
                if case .createEngine = event { count += 1 }
            }
        }
    }

    func releaseCount() async -> Int {
        lock.withLock { recordedEvents.filter { $0 == .release }.count }
    }

    func latestDelegate() async -> PingScopeCKSyncEngineDelegate? {
        lock.withLock { delegates.values.first }
    }

    func statePresenceAtEngineCreation() async -> [Bool] {
        lock.withLock { recordedStatePresenceAtEngineCreation }
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
    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        uploadedRecordCount += records.count
        return CloudSyncUploadConfirmation(confirming: records)
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
    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        uploads += 1
        return CloudSyncUploadConfirmation(confirming: records)
    }
    func stopCount() -> Int { stops }
    func uploadCount() -> Int { uploads }
}

private actor GatedInFlightUploadBoundary: CloudSyncEngineBoundary {
    private var availability: CloudSyncAccountAvailability = .privateAccount
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var uploadContinuation: CheckedContinuation<Void, Never>?
    private var uploadStartWaiters: [CheckedContinuation<Void, Never>] = []

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
        _ = deletions
        let waiters = uploadStartWaiters
        uploadStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { uploadContinuation = $0 }
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func waitForUploadStart() async {
        guard uploadContinuation == nil else { return }
        await withCheckedContinuation { uploadStartWaiters.append($0) }
    }

    func emitAccountChange(availability: CloudSyncAccountAvailability) async {
        self.availability = availability
        let handler = accountChangeHandler
        await handler?()
    }

    func releaseUpload() {
        let continuation = uploadContinuation
        uploadContinuation = nil
        continuation?.resume()
    }
}

private actor LifecycleRecordingBoundary: CloudSyncEngineBoundary {
    private var availability: CloudSyncAccountAvailability = .privateAccount
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var uploads = 0

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
        _ = deletions
        uploads += 1
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func emitAccountChange(availability: CloudSyncAccountAvailability) async {
        self.availability = availability
        let handler = accountChangeHandler
        await handler?()
    }

    func uploadCount() -> Int { uploads }
}

private actor GatedCloudSyncRecordBuilder: CloudSyncRecordBuilding {
    private var sampleBuildContinuation: CheckedContinuation<Void, Never>?
    private var sampleBuildWaiters: [CheckedContinuation<Void, Never>] = []

    func sampleRecord(from sample: PingResult) async -> CKRecord {
        let waiters = sampleBuildWaiters
        sampleBuildWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { sampleBuildContinuation = $0 }
        return PingSampleRecordMapper.record(from: sample)
    }

    func hostRecord(from host: CloudSyncHostVersion) async throws -> CKRecord {
        try MonitoredHostRecordMapper.record(from: host.config, modifiedAt: host.modifiedAt)
    }

    func waitForSampleBuildStart() async {
        guard sampleBuildContinuation == nil else { return }
        await withCheckedContinuation { sampleBuildWaiters.append($0) }
    }

    func releaseSampleBuild() {
        let continuation = sampleBuildContinuation
        sampleBuildContinuation = nil
        continuation?.resume()
    }
}

private actor GatedLifecycleBoundary: CloudSyncEngineBoundary {
    private var handlerClearContinuation: CheckedContinuation<Void, Never>?
    private var handlerClearWaiters: [CheckedContinuation<Void, Never>] = []
    private var handlerClearStarted = false
    private var handlerClearReleased = false
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var stopStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopStarted = false
    private var stopReleased = false
    private var shouldSuspendHandlerClear = false
    private var shouldSuspendStops = false
    private var running = false

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }

    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async {
        guard handler == nil, shouldSuspendHandlerClear else { return }
        handlerClearStarted = true
        let waiters = handlerClearWaiters
        handlerClearWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            if handlerClearReleased {
                continuation.resume()
            } else {
                handlerClearContinuation = continuation
            }
        }
    }

    func start() async throws { running = true }

    func stop() async {
        stopStarted = true
        let waiters = stopStartWaiters
        stopStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if shouldSuspendStops {
            await withCheckedContinuation { continuation in
                if stopReleased {
                    continuation.resume()
                } else {
                    stopContinuation = continuation
                }
            }
        }
        running = false
    }

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        _ = deletions
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func suspendHandlerClear() { shouldSuspendHandlerClear = true }
    func suspendStops() { shouldSuspendStops = true }

    func handlerClearHasStarted() -> Bool { handlerClearStarted }
    func stopHasStarted() -> Bool { stopStarted }

    func releaseHandlerClear() {
        handlerClearReleased = true
        let continuation = handlerClearContinuation
        handlerClearContinuation = nil
        continuation?.resume()
    }

    func releaseStops() {
        shouldSuspendStops = false
        stopReleased = true
        let continuation = stopContinuation
        stopContinuation = nil
        continuation?.resume()
    }

    func isRunning() -> Bool { running }
}

private actor RecoveryCallbackGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private actor DisableTeardownGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private actor GatedStartupBoundary: CloudSyncEngineBoundary {
    private let gateInitialStart: Bool
    private var accountChangeHandler: (@Sendable () async -> Void)?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var starts = 0
    private var running = false

    init(gateInitialStart: Bool) {
        self.gateInitialStart = gateInitialStart
    }

    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }

    func setAccountChangeHandler(_ handler: (@Sendable () async -> Void)?) async {
        accountChangeHandler = handler
    }

    func start() async throws {
        starts += 1
        if gateInitialStart, starts == 1 {
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { startContinuation = $0 }
        }
        running = true
    }

    func stop() async { running = false }

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        _ = deletions
        return CloudSyncUploadConfirmation(confirming: records)
    }

    func emitAccountChange() async {
        running = false
        let handler = accountChangeHandler
        await handler?()
    }

    func waitForGatedStart() async {
        guard startContinuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseStart() {
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume()
    }

    func startCount() -> Int { starts }
    func isRunning() -> Bool { running }
}

private enum ThrowingCloudSyncRecordBuilderError: Error {
    case forced
}

private struct ThrowingHostRecordBuilder: CloudSyncRecordBuilding {
    func sampleRecord(from sample: PingResult) async -> CKRecord {
        PingSampleRecordMapper.record(from: sample)
    }

    func hostRecord(from host: CloudSyncHostVersion) async throws -> CKRecord {
        _ = host
        throw ThrowingCloudSyncRecordBuilderError.forced
    }
}

private enum ThrowingUploadBoundaryError: Error {
    case forced
}

private actor ThrowingUploadBoundary: CloudSyncEngineBoundary {
    func accountAvailability() async -> CloudSyncAccountAvailability { .privateAccount }
    func start() async throws {}
    func stop() async {}

    func upload(
        records: [CKRecord],
        deletions: [CKRecord.ID]
    ) async throws -> CloudSyncUploadConfirmation {
        _ = records
        _ = deletions
        throw ThrowingUploadBoundaryError.forced
    }
}
