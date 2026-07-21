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
