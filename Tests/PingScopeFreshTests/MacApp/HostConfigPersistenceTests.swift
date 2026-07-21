import XCTest
@testable import PingScope
import PingScopeCore

final class HostConfigPersistenceTests: XCTestCase {
    func testMacPersistenceMigratesLegacyHostsToSharedStoreOnSuccessfulPersist() throws {
        let suiteName = "HostConfigPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hosts = [
            HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1", tier: .localGateway),
            HostConfig(id: UUID(), displayName: "Office", address: "office.example", tier: .remoteService),
            HostConfig(id: UUID(), displayName: "DNS", address: "9.9.9.9", tier: .upstream)
        ]
        defaults.set(try JSONEncoder().encode(hosts), forKey: SharedHostStoreKeys.macHosts)
        defaults.primaryHostID = hosts[1].id
        let persistence = HostConfigPersistence(defaults: defaults)

        let loaded = persistence.loadInitialConfiguration { _ in }

        XCTAssertEqual(loaded.hosts, hosts)
        XCTAssertEqual(loaded.primaryHostID, hosts[1].id)
        XCTAssertNil(defaults.data(forKey: SharedHostStoreKeys.current))

        persistence.persist(
            RuntimeSnapshot(hosts: hosts, primaryHostID: hosts[1].id, healthByHost: [:], samplesByHost: [:])
        ) { _ in }

        let sharedData = try XCTUnwrap(defaults.data(forKey: SharedHostStoreKeys.current))
        XCTAssertEqual(
            try SharedHostStoreCodec.decode(sharedData),
            SharedHostStoreState(hosts: hosts, primaryHostID: hosts[1].id)
        )
        XCTAssertNotNil(defaults.data(forKey: SharedHostStoreKeys.macHosts))
    }

    func testLegacyDefaultHostsGainGoogleDNSOnce() throws {
        let suiteName = "HostConfigPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyHosts = [
            HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", method: .https, port: 443),
            HostConfig.defaultGatewayHost(address: "192.168.42.1")
        ]
        try defaults.setHostConfigs(legacyHosts)

        let loaded = HostConfigPersistence(defaults: defaults).loadInitialConfiguration { _ in }

        XCTAssertEqual(loaded.hosts.map(\.displayName), ["Cloudflare DNS", "Google DNS", "Default Gateway"])
        XCTAssertTrue(defaults.bool(forKey: "didSeedDefaultHosts"))
    }

    func testUserManagedHostsDoNotGainGoogleDNS() throws {
        let suiteName = "HostConfigPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hosts = [
            HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", method: .https, port: 443),
            HostConfig(displayName: "Router", address: "192.168.42.1", tier: .localGateway),
            HostConfig(displayName: "Office VPN", address: "10.0.0.8", tier: .remoteService)
        ]
        try defaults.setHostConfigs(hosts)

        let loaded = HostConfigPersistence(defaults: defaults).loadInitialConfiguration { _ in }

        XCTAssertEqual(loaded.hosts.map(\.displayName), ["Cloudflare DNS", "Router", "Office VPN"])
        XCTAssertFalse(loaded.hosts.contains { $0.displayName == "Google DNS" })
        XCTAssertTrue(defaults.bool(forKey: "didSeedDefaultHosts"))
    }

    func testDeletedDefaultHostIsNotReseededOnSubsequentLoad() throws {
        let suiteName = "HostConfigPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = HostConfigPersistence(defaults: defaults)

        let initial = persistence.loadInitialConfiguration { _ in }

        XCTAssertEqual(initial.hosts.map(\.displayName), ["Cloudflare DNS", "Google DNS", "Default Gateway"])
        XCTAssertNotNil(defaults.data(forKey: "hostConfigs"))

        let editedHosts = initial.hosts.filter { $0.displayName != "Google DNS" }
        try defaults.setHostConfigs(editedHosts)
        defaults.primaryHostID = editedHosts.first?.id

        let reloaded = HostConfigPersistence(defaults: defaults).loadInitialConfiguration { _ in }

        XCTAssertEqual(reloaded.hosts.map(\.displayName), ["Cloudflare DNS", "Default Gateway"])
        XCTAssertFalse(reloaded.hosts.contains { $0.displayName == "Google DNS" })
    }

    @MainActor
    func testMacHostDraftSavesCustomAndAutomaticColorWithoutChangingProbeConfiguration() throws {
        let customColor = HostDisplayColor(red: 0.15, green: 0.45, blue: 0.75)
        let host = HostConfig(
            id: UUID(),
            displayName: "Edge",
            address: "edge.example",
            tier: .remoteService,
            method: .tcp,
            port: 8443,
            interval: .milliseconds(1_250),
            timeout: .milliseconds(2_750),
            thresholds: LatencyThresholds(degradedMilliseconds: 240, downAfterFailures: 4),
            isEnabled: false,
            notifications: .muted,
            displayColor: nil
        )
        let model = PingScopeModel()

        model.loadDraft(from: host)
        model.draftDisplayColor = customColor
        model.addDraftHost()

        let saved = try XCTUnwrap(model.snapshot.hosts.first { $0.id == host.id })
        XCTAssertEqual(saved.displayColor, customColor)
        XCTAssertEqual(saved.displayName, host.displayName)
        XCTAssertEqual(saved.address, host.address)
        XCTAssertEqual(saved.tier, host.tier)
        XCTAssertEqual(saved.method, host.method)
        XCTAssertEqual(saved.port, host.port)
        XCTAssertEqual(saved.interval, host.interval)
        XCTAssertEqual(saved.timeout, host.timeout)
        XCTAssertEqual(saved.thresholds, host.thresholds)
        XCTAssertEqual(saved.isEnabled, host.isEnabled)
        XCTAssertEqual(saved.notifications, host.notifications)

        model.loadDraft(from: saved)
        XCTAssertEqual(model.draftDisplayColor, customColor)
        model.draftDisplayColor = nil
        model.addDraftHost()

        let automatic = try XCTUnwrap(model.snapshot.hosts.first { $0.id == host.id })
        XCTAssertNil(automatic.displayColor)
        XCTAssertEqual(automatic.address, host.address)
        XCTAssertEqual(automatic.method, host.method)
        XCTAssertEqual(automatic.port, host.port)
        XCTAssertEqual(automatic.interval, host.interval)
        XCTAssertEqual(automatic.timeout, host.timeout)
    }

    @MainActor
    func testMacHostDraftTreatsInvalidDecodableColorsAsAutomaticAndClearsThemOnSave() throws {
        for invalidColor in [
            HostDisplayColor(red: -0.1, green: 0.4, blue: 0.8),
            HostDisplayColor(red: .nan, green: 0.4, blue: 0.8),
        ] {
            let host = HostConfig(id: UUID(), displayName: "Invalid", address: "invalid.example", displayColor: invalidColor)
            let model = PingScopeModel()

            model.loadDraft(from: host)

            XCTAssertNil(model.draftDisplayColor)
            model.addDraftHost()
            XCTAssertNil(try XCTUnwrap(model.snapshot.hosts.first { $0.id == host.id }).displayColor)
        }
    }

    @MainActor
    func testMacModelColorSavePreservesRuntimeGenerationAndSamplesButProbeEditRestarts() async throws {
        let host = HostConfig.defaultInternet
        let tracker = MacProbeCancellationTracker()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: MacCancellationTrackingProbeFactory(tracker: tracker))
        )
        let model = PingScopeModel(runtimeForTesting: runtime)
        await runtime.start()
        try await tracker.waitUntilMeasurementStarts()
        let sample = PingResult.success(hostID: host.id, latency: .milliseconds(12))
        await runtime.ingest(sample)

        model.loadDraft(from: host)
        model.draftDisplayColor = HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        model.addDraftHost()
        try await waitUntilRuntimeHost(runtime, hostID: host.id) { $0.displayColor != nil }

        var snapshot = try await currentSnapshot(runtime)
        let cancellationCount = await tracker.cancellations()
        XCTAssertEqual(cancellationCount, 0)
        XCTAssertEqual(snapshot.samplesByHost[host.id]?.samples, [sample])

        let recolored = try XCTUnwrap(snapshot.hosts.first { $0.id == host.id })
        model.loadDraft(from: recolored)
        model.draftTimeoutMilliseconds = 3_000
        model.addDraftHost()
        try await tracker.waitForCancellations(atLeast: 1)

        snapshot = try await currentSnapshot(runtime)
        XCTAssertEqual(snapshot.primaryHost?.timeout, .milliseconds(3_000))
        await runtime.stop()
    }

    @MainActor
    func testMacModelReconcilesAcceptedRemoteColorThroughRuntimePresentationAndWidgetState() async throws {
        let suite = "MacAcceptedRemoteColor.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = HostConfig(id: UUID(), displayName: "Edge", address: "edge.example")
        let sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try sharedStore.save(SharedHostStoreState(hosts: [host], primaryHostID: host.id))
        let tracker = MacProbeCancellationTracker()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host], primaryHostID: host.id),
            scheduler: MeasurementScheduler(probeFactory: MacCancellationTrackingProbeFactory(tracker: tracker))
        )
        let model = PingScopeModel(cloudSyncDefaultsSuiteName: suite, runtimeOverride: runtime)
        model.overlayShowsAllHosts = true
        let retainedSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(21),
            timestamp: Date()
        )
        await runtime.ingest(retainedSample)
        await runtime.start()
        try await tracker.waitUntilMeasurementStarts()
        var remote = host
        remote.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        let acceptedState = SharedHostStoreState(hosts: [remote], primaryHostID: host.id)
        try sharedStore.save(acceptedState)

        await model.reconcileAcceptedCloudHostState(acceptedState)

        XCTAssertEqual(model.snapshot.primaryHost, remote)
        XCTAssertEqual(model.snapshot.primarySeries?.samples, [retainedSample])
        let widgetSnapshot = WidgetSnapshot.make(from: model.snapshot)
        XCTAssertEqual(
            widgetSnapshot.hosts.first?.displayColor,
            WidgetHostDisplayColor(resolvedColor: ResolvedHostDisplayColor(hostID: host.id, displayColor: remote.displayColor))
        )
        try await Task.sleep(for: .milliseconds(250))
        let remoteColor = try XCTUnwrap(remote.displayColor)
        XCTAssertEqual(model.displayPresentation.allHostGraphSeries.first?.resolvedColor, .custom(remoteColor))
        let cancellationsAfterRemoteEdit = await tracker.cancellations()
        XCTAssertEqual(cancellationsAfterRemoteEdit, 0)

        model.loadDraft(from: try XCTUnwrap(model.snapshot.primaryHost))
        model.draftNotificationPolicy = .muted
        model.addDraftHost()
        try await waitUntilRuntimeHost(runtime, hostID: host.id) { $0.notifications == .muted }
        let afterLocalEdit = try await currentSnapshot(runtime)
        XCTAssertEqual(afterLocalEdit.primaryHost?.displayColor, remote.displayColor)
        XCTAssertEqual(afterLocalEdit.primarySeries?.samples, [retainedSample])
        let cancellationsAfterLocalEdit = await tracker.cancellations()
        XCTAssertEqual(cancellationsAfterLocalEdit, 0)
        await runtime.stop()
    }

    @MainActor
    func testMacBlockedAcceptedDeliveryKeepsRemoteColorAndConcurrentUnrelatedLocalEdit() async throws {
        let suite = "MacAcceptedDeliveryRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = HostConfig(id: UUID(), displayName: "Edge", address: "edge.example")
        let peer = HostConfig(id: UUID(), displayName: "Peer", address: "peer.example")
        let sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try sharedStore.save(SharedHostStoreState(hosts: [host, peer], primaryHostID: host.id))
        let localPersistence = HostConfigPersistence(defaults: defaults)
        _ = localPersistence.loadInitialConfiguration { _ in }
        let tracker = MacProbeCancellationTracker()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host, peer], primaryHostID: host.id),
            scheduler: MeasurementScheduler(probeFactory: MacCancellationTrackingProbeFactory(tracker: tracker))
        )
        let model = PingScopeModel(cloudSyncDefaultsSuiteName: suite, runtimeOverride: runtime)
        let retainedSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(21),
            timestamp: Date()
        )
        await runtime.ingest(retainedSample)
        await runtime.start()
        try await tracker.waitUntilMeasurementStarts()
        var remoteHost = host
        remoteHost.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        let capturedRemoteState = SharedHostStoreState(
            hosts: [remoteHost, peer],
            primaryHostID: host.id
        )
        try sharedStore.save(capturedRemoteState)
        let deliveryGate = MacAcceptedHostDeliveryGate()
        let delivery = Task { @MainActor in
            await deliveryGate.block()
            await model.reconcileAcceptedCloudHostState(capturedRemoteState)
        }
        await deliveryGate.waitUntilBlocked()

        var locallyEditedPeer = peer
        locallyEditedPeer.notifications = .muted
        localPersistence.persist(
            RuntimeSnapshot(
                hosts: [host, locallyEditedPeer],
                primaryHostID: host.id,
                healthByHost: [:],
                samplesByHost: [:]
            ),
            logger: { _ in }
        )
        await runtime.upsertHost(locallyEditedPeer)
        await deliveryGate.release()
        await delivery.value

        let snapshot = model.snapshot
        XCTAssertEqual(snapshot.hosts.first { $0.id == host.id }?.displayColor, remoteHost.displayColor)
        XCTAssertEqual(snapshot.hosts.first { $0.id == peer.id }?.notifications, .muted)
        XCTAssertEqual(snapshot.samplesByHost[host.id]?.samples, [retainedSample])
        let cancellationCount = await tracker.cancellations()
        XCTAssertEqual(cancellationCount, 0)
        await runtime.stop()
    }

    @MainActor
    func testMacLocalSaveAfterAcceptedResolutionCannotRollbackModelRuntimeStoreOrUploads() async throws {
        let suite = "MacAcceptedCommitRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = HostConfig(id: UUID(), displayName: "Edge", address: "edge.example")
        let peer = HostConfig(id: UUID(), displayName: "Peer", address: "peer.example")
        let sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try sharedStore.save(SharedHostStoreState(hosts: [host, peer], primaryHostID: host.id))
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host, peer], primaryHostID: host.id),
            scheduler: MeasurementScheduler(probeFactory: DefaultProbeFactory())
        )
        let retainedSample = PingResult.success(hostID: host.id, latency: .milliseconds(19))
        await runtime.ingest(retainedSample)
        let commitGate = MacAcceptedHostDeliveryGate()
        let uploadRecorder = MacHostUploadRecorder()
        let model = PingScopeModel(
            cloudSyncDefaultsSuiteName: suite,
            runtimeOverride: runtime,
            acceptedHostReconciliationGate: { await commitGate.block() },
            cloudHostUploadObserver: uploadRecorder.record
        )
        var remoteHost = host
        remoteHost.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        let capturedRemoteState = SharedHostStoreState(
            hosts: [remoteHost, peer],
            primaryHostID: host.id
        )
        try sharedStore.save(capturedRemoteState)

        let delivery = Task { @MainActor in
            await model.reconcileAcceptedCloudHostState(capturedRemoteState)
        }
        await commitGate.waitUntilBlocked()

        model.loadDraft(from: peer)
        model.draftNotificationPolicy = .muted
        model.addDraftHost()
        await commitGate.release()
        await delivery.value
        try await waitUntilRuntimeHost(runtime, hostID: peer.id) { $0.notifications == .muted }
        await model.waitForHostMutationCommits()

        var locallyEditedPeer = peer
        locallyEditedPeer.notifications = .muted
        let expectedHosts = [remoteHost, locallyEditedPeer]
        XCTAssertEqual(model.snapshot.hosts, expectedHosts)
        let runtimeSnapshot = try await currentSnapshot(runtime)
        XCTAssertEqual(runtimeSnapshot.hosts, expectedHosts)
        XCTAssertEqual(runtimeSnapshot.samplesByHost[host.id]?.samples, [retainedSample])
        XCTAssertEqual(sharedStore.load().state?.hosts, expectedHosts)
        XCTAssertEqual(uploadRecorder.values(), [expectedHosts])
    }

    @MainActor
    func testMacAcceptedDeliveryWaitsForIntervalMutationRuntimeStoreAndModelCommit() async throws {
        let suite = "MacAcceptedMutationBarrier.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = HostConfig(id: UUID(), displayName: "Edge", address: "edge.example")
        let peer = HostConfig(id: UUID(), displayName: "Peer", address: "peer.example")
        let sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try sharedStore.save(SharedHostStoreState(hosts: [host, peer], primaryHostID: host.id))
        let runtimeCommitGate = MacBlockedProbeCancellationGate()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host, peer], primaryHostID: host.id),
            scheduler: MeasurementScheduler(
                probeFactory: MacBlockedCancellationProbeFactory(gate: runtimeCommitGate)
            )
        )
        let acceptedCommitGate = MacAcceptedHostDeliveryGate()
        let uploadRecorder = MacHostUploadRecorder()
        let model = PingScopeModel(
            cloudSyncDefaultsSuiteName: suite,
            runtimeOverride: runtime,
            acceptedHostReconciliationGate: { await acceptedCommitGate.block() },
            cloudHostUploadObserver: uploadRecorder.record
        )
        await runtime.start()
        try await runtimeCommitGate.waitUntilMeasurementStarts()
        let retainedSample = PingResult.success(hostID: host.id, latency: .milliseconds(23))
        await runtime.ingest(retainedSample)

        var remotelyEditedPeer = peer
        remotelyEditedPeer.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        let capturedRemoteState = SharedHostStoreState(
            hosts: [host, remotelyEditedPeer],
            primaryHostID: host.id
        )
        try sharedStore.save(capturedRemoteState)

        model.setPingInterval(.seconds(3), for: host.id)
        try await runtimeCommitGate.waitUntilCancellationStarts()
        let delivery = Task { @MainActor in
            await model.reconcileAcceptedCloudHostState(capturedRemoteState)
        }
        for _ in 0..<50 where !(await acceptedCommitGate.blocked()) {
            try await Task.sleep(for: .milliseconds(1))
        }
        let acceptedEnteredBeforeLocalCommit = await acceptedCommitGate.blocked()

        await runtimeCommitGate.release()
        await acceptedCommitGate.waitUntilBlocked()
        await acceptedCommitGate.release()
        await delivery.value

        var locallyEditedHost = host
        locallyEditedHost.interval = .seconds(3)
        let expectedHosts = [locallyEditedHost, remotelyEditedPeer]
        let runtimeSnapshot = try await currentSnapshot(runtime)
        XCTAssertFalse(acceptedEnteredBeforeLocalCommit)
        XCTAssertEqual(model.snapshot.hosts, expectedHosts)
        XCTAssertEqual(model.snapshot.samplesByHost[host.id]?.samples, [retainedSample])
        XCTAssertEqual(runtimeSnapshot.hosts, expectedHosts)
        XCTAssertEqual(runtimeSnapshot.samplesByHost[host.id]?.samples, [retainedSample])
        XCTAssertEqual(sharedStore.load().state?.hosts, expectedHosts)
        XCTAssertEqual(uploadRecorder.values(), [expectedHosts])
        await runtime.stop()
    }

    func testMacSharedHostStoreSameHostLaterLocalEditWinsWholeHostConflict() throws {
        let suite = "MacAcceptedDeliverySameHost.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = HostConfig(id: UUID(), displayName: "Edge", address: "edge.example")
        let sharedStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try sharedStore.save(SharedHostStoreState(hosts: [host], primaryHostID: host.id))
        let persistence = HostConfigPersistence(defaults: defaults)
        _ = persistence.loadInitialConfiguration { _ in }
        var remote = host
        remote.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        try sharedStore.save(SharedHostStoreState(hosts: [remote], primaryHostID: host.id))
        var laterLocal = host
        laterLocal.displayName = "Locally Renamed"
        laterLocal.notifications = .muted

        persistence.persist(
            RuntimeSnapshot(
                hosts: [laterLocal],
                primaryHostID: host.id,
                healthByHost: [:],
                samplesByHost: [:]
            ),
            logger: { _ in }
        )

        XCTAssertEqual(sharedStore.load().state?.hosts, [laterLocal])
    }
}

private func currentSnapshot(_ runtime: PingRuntime) async throws -> RuntimeSnapshot {
    let stream = await runtime.snapshots()
    var iterator = stream.makeAsyncIterator()
    guard let snapshot = await iterator.next() else { throw MacRuntimeTestTimeout() }
    return snapshot
}

@MainActor
private func waitUntilRuntimeHost(
    _ runtime: PingRuntime,
    hostID: UUID,
    matches: (HostConfig) -> Bool
) async throws {
    for _ in 0..<100 {
        let snapshot = try await currentSnapshot(runtime)
        if let host = snapshot.hosts.first(where: { $0.id == hostID }), matches(host) { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw MacRuntimeTestTimeout()
}

private struct MacRuntimeTestTimeout: Error {}

private actor MacAcceptedHostDeliveryGate {
    private var isBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        isBlocked = true
        blockedWaiters.forEach { $0.resume() }
        blockedWaiters.removeAll()
        while !isReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func waitUntilBlocked() async {
        while !isBlocked {
            await withCheckedContinuation { blockedWaiters.append($0) }
        }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    func blocked() -> Bool {
        isBlocked
    }
}

private final class MacHostUploadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var uploads: [[HostConfig]] = []

    func record(_ hosts: [HostConfig]) {
        lock.withLock { uploads.append(hosts) }
    }

    func values() -> [[HostConfig]] {
        lock.withLock { uploads }
    }
}

private actor MacProbeCancellationTracker {
    private var started = false
    private var cancellationCount = 0

    func markStarted() { started = true }
    func markCancelled() { cancellationCount += 1 }
    func cancellations() -> Int { cancellationCount }

    func waitUntilMeasurementStarts() async throws {
        for _ in 0..<100 where !started { try await Task.sleep(for: .milliseconds(10)) }
        if !started { throw MacRuntimeTestTimeout() }
    }

    func waitForCancellations(atLeast count: Int) async throws {
        for _ in 0..<100 where cancellationCount < count { try await Task.sleep(for: .milliseconds(10)) }
        if cancellationCount < count { throw MacRuntimeTestTimeout() }
    }
}

private struct MacCancellationTrackingProbeFactory: ProbeFactory {
    let tracker: MacProbeCancellationTracker
    func makeProbe(for method: PingMethod) async -> any PingProbe { MacCancellationTrackingProbe(tracker: tracker) }
}

private struct MacCancellationTrackingProbe: PingProbe {
    let tracker: MacProbeCancellationTracker
    func measure(_ host: HostConfig) async -> PingResult {
        await tracker.markStarted()
        return await withTaskCancellationHandler {
            try? await Task.sleep(for: .seconds(60))
            return .failure(hostID: host.id, reason: .timeout)
        } onCancel: {
            Task { await tracker.markCancelled() }
        }
    }
}

private actor MacBlockedProbeCancellationGate {
    private var measurementStarted = false
    private var cancellationStarted = false
    private var isReleased = false
    private var measurementWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markMeasurementStarted() {
        measurementStarted = true
        measurementWaiters.forEach { $0.resume() }
        measurementWaiters.removeAll()
    }

    func markCancellationStarted() {
        cancellationStarted = true
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
    }

    func waitUntilMeasurementStarts() async throws {
        while !measurementStarted {
            await withCheckedContinuation { measurementWaiters.append($0) }
        }
    }

    func waitUntilCancellationStarts() async throws {
        while !cancellationStarted {
            await withCheckedContinuation { cancellationWaiters.append($0) }
        }
    }

    func waitForRelease() async {
        while !isReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private struct MacBlockedCancellationProbeFactory: ProbeFactory {
    let gate: MacBlockedProbeCancellationGate

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        MacBlockedCancellationProbe(gate: gate)
    }
}

private struct MacBlockedCancellationProbe: PingProbe {
    let gate: MacBlockedProbeCancellationGate

    func measure(_ host: HostConfig) async -> PingResult {
        await gate.markMeasurementStarted()
        return await withTaskCancellationHandler {
            await gate.waitForRelease()
            try? await Task.sleep(for: .seconds(60))
            return .failure(hostID: host.id, reason: .timeout)
        } onCancel: {
            Task { await gate.markCancellationStarted() }
        }
    }
}
