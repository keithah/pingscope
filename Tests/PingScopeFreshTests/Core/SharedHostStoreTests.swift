import Foundation
import XCTest
@testable import PingScopeCore

final class SharedHostStoreTests: XCTestCase {
    func testMacLegacyStoreLoadsWithoutWritingForwardUntilSave() throws {
        try withDefaults { defaults in
            let hosts = [
                HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1"),
                HostConfig(id: UUID(), displayName: "DNS", address: "1.1.1.1")
            ]
            let legacyData = try JSONEncoder().encode(hosts)
            defaults.set(legacyData, forKey: SharedHostStoreKeys.macHosts)
            defaults.set(hosts[1].id.uuidString, forKey: SharedHostStoreKeys.macPrimaryHostID)
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)

            let loaded = store.load()

            XCTAssertEqual(loaded.source, .legacy)
            XCTAssertEqual(loaded.state, SharedHostStoreState(hosts: hosts, primaryHostID: hosts[1].id))
            XCTAssertNil(defaults.data(forKey: SharedHostStoreKeys.current))
            XCTAssertEqual(defaults.data(forKey: SharedHostStoreKeys.macHosts), legacyData)

            try store.save(try XCTUnwrap(loaded.state))
            XCTAssertNotNil(defaults.data(forKey: SharedHostStoreKeys.current))
            XCTAssertNotNil(defaults.data(forKey: SharedHostStoreKeys.macHosts))
            XCTAssertEqual(try SharedHostStoreCodec.decode(XCTUnwrap(defaults.data(forKey: SharedHostStoreKeys.current))), loaded.state)
        }
    }

    func testIOSLegacyStoreLoadsHostsAndSelectedHostThenWritesSharedShape() throws {
        try withDefaults { defaults in
            let hosts = [
                HostConfig(id: UUID(), displayName: "First", address: "1.1.1.1"),
                HostConfig(id: UUID(), displayName: "Second", address: "8.8.8.8")
            ]
            let legacyData = try JSONEncoder().encode(hosts)
            defaults.set(legacyData, forKey: SharedHostStoreKeys.iOSHosts)
            defaults.set(hosts[1].id.uuidString, forKey: SharedHostStoreKeys.iOSSelectedHostID)
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .iOS)

            let loaded = store.load()

            XCTAssertEqual(loaded.source, .legacy)
            XCTAssertEqual(loaded.state, SharedHostStoreState(hosts: hosts, selectedHostID: hosts[1].id))
            XCTAssertNil(defaults.data(forKey: SharedHostStoreKeys.current))
            XCTAssertEqual(defaults.data(forKey: SharedHostStoreKeys.iOSHosts), legacyData)

            try store.save(try XCTUnwrap(loaded.state))
            XCTAssertEqual(try SharedHostStoreCodec.decode(XCTUnwrap(defaults.data(forKey: SharedHostStoreKeys.current))), loaded.state)
            XCTAssertNotNil(defaults.data(forKey: SharedHostStoreKeys.iOSHosts))
        }
    }

    func testFiniteLegacyMirrorRemainsReadableByDefaultPreM9Decoder() throws {
        try withDefaults { defaults in
            let hosts = [
                HostConfig(
                    id: UUID(),
                    displayName: "Finite",
                    address: "finite.example",
                    thresholds: LatencyThresholds(degradedMilliseconds: 123.5, downAfterFailures: 4)
                )
            ]
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)

            try store.save(SharedHostStoreState(hosts: hosts, primaryHostID: hosts[0].id))

            let legacyData = try XCTUnwrap(defaults.data(forKey: SharedHostStoreKeys.macHosts))
            XCTAssertEqual(try JSONDecoder().decode([HostConfig].self, from: legacyData), hosts)
        }
    }

    func testNonFiniteLegacyEncodeFailureKeepsSuccessfulSharedWriteAndExistingLegacyMirror() throws {
        try withDefaults { defaults in
            let oldHosts = [HostConfig(id: UUID(), displayName: "Old", address: "old.example")]
            let oldLegacyData = try JSONEncoder().encode(oldHosts)
            defaults.set(oldLegacyData, forKey: SharedHostStoreKeys.macHosts)
            let host = HostConfig(
                id: UUID(),
                displayName: "Non-finite",
                address: "new.example",
                thresholds: LatencyThresholds(degradedMilliseconds: .nan, downAfterFailures: 3)
            )
            let state = SharedHostStoreState(hosts: [host], primaryHostID: host.id)
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)

            XCTAssertThrowsError(try store.save(state))

            let sharedData = try XCTUnwrap(defaults.data(forKey: SharedHostStoreKeys.current))
            let decoded = try SharedHostStoreCodec.decode(sharedData)
            XCTAssertTrue(try XCTUnwrap(decoded.hosts.first).thresholds.degradedMilliseconds.isNaN)
            XCTAssertEqual(decoded.primaryHostID, host.id)
            XCTAssertEqual(defaults.data(forKey: SharedHostStoreKeys.macHosts), oldLegacyData)
        }
    }

    func testOverlappingReceiverThenLocalSavePreservesBothWritersAndReceiverWinsSameHost() async throws {
        let scenario = SharedHostStoreOverlapScenario()
        let suiteName = "SharedHostStoreOverlapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let receiverStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        let localStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)
        try receiverStore.save(scenario.initialState)
        let receiverGate = SharedHostStoreOverlapGate()

        let receiver = Task.detached {
            _ = receiverStore.load()
            await receiverGate.blockAfterLoad()
            try receiverStore.save(scenario.receiverState)
        }
        await receiverGate.waitUntilBlocked()
        _ = localStore.load()
        try localStore.save(scenario.localState)
        await receiverGate.release()
        try await receiver.value

        let finalState = try XCTUnwrap(receiverStore.load().state)
        XCTAssertEqual(finalState.hosts, scenario.receiverWinsHosts)
        XCTAssertEqual(finalState.primaryHostID, scenario.receiverOnly.id)
        XCTAssertEqual(finalState.selectedHostID, scenario.localOnly.id)
    }

    func testOverlappingLocalThenReceiverSavePreservesBothWritersAndLocalWinsSameHost() async throws {
        let scenario = SharedHostStoreOverlapScenario()
        let suiteName = "SharedHostStoreOverlapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let receiverStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .iOS)
        let localStore = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .iOS)
        try receiverStore.save(scenario.initialState)
        let localGate = SharedHostStoreOverlapGate()

        let local = Task.detached {
            _ = localStore.load()
            await localGate.blockAfterLoad()
            try localStore.save(scenario.localState)
        }
        await localGate.waitUntilBlocked()
        _ = receiverStore.load()
        try receiverStore.save(scenario.receiverState)
        await localGate.release()
        try await local.value

        let finalState = try XCTUnwrap(localStore.load().state)
        XCTAssertEqual(finalState.hosts, scenario.localWinsHosts)
        XCTAssertEqual(finalState.primaryHostID, scenario.receiverOnly.id)
        XCTAssertEqual(finalState.selectedHostID, scenario.localOnly.id)
    }

    func testStoreFallsBackToLegacyForMalformedOrFutureSharedData() throws {
        try withDefaults { defaults in
            let hosts = [HostConfig(id: UUID(), displayName: "Legacy", address: "9.9.9.9")]
            defaults.set(try JSONEncoder().encode(hosts), forKey: SharedHostStoreKeys.macHosts)
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .macOS)

            defaults.set(Data("malformed".utf8), forKey: SharedHostStoreKeys.current)
            XCTAssertEqual(store.load().state?.hosts, hosts)
            XCTAssertEqual(store.load().source, .legacy)

            let current = try SharedHostStoreCodec.encode(SharedHostStoreState(hosts: hosts))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
            object["schemaVersion"] = 999
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: SharedHostStoreKeys.current)
            XCTAssertEqual(store.load().state?.hosts, hosts)
            XCTAssertEqual(store.load().source, .legacy)
        }
    }

    func testStoreMissingOrMalformedWithoutLegacyFailsSafe() throws {
        try withDefaults { defaults in
            let store = UserDefaultsSharedHostStore(defaults: defaults, legacyPlatform: .iOS)
            XCTAssertEqual(store.load().source, .missing)
            XCTAssertNil(store.load().state)

            defaults.set(Data("malformed".utf8), forKey: SharedHostStoreKeys.current)
            XCTAssertEqual(store.load().source, .unreadable)
            XCTAssertNil(store.load().state)
        }
    }

    func testSharedHostStoreCodecRoundTripsEveryHostFieldAndSelectionWithoutReordering() throws {
        let first = HostConfig(
            id: UUID(),
            displayName: "Starlink Dish",
            address: "192.168.100.1",
            tier: .ispEdge,
            method: .starlink,
            port: 9200,
            interval: .milliseconds(750),
            timeout: .milliseconds(1_250),
            thresholds: LatencyThresholds(degradedMilliseconds: 187.5, downAfterFailures: 7),
            isEnabled: false,
            notifications: .enabled,
            displayColor: HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        )
        let second = HostConfig(
            id: UUID(),
            displayName: "Office DNS",
            address: "10.0.0.53",
            tier: .localGateway,
            method: .udp,
            port: 53,
            interval: .seconds(3),
            timeout: .milliseconds(900),
            thresholds: LatencyThresholds(degradedMilliseconds: 42, downAfterFailures: 2),
            notifications: .muted
        )
        let state = SharedHostStoreState(
            hosts: [second, first],
            primaryHostID: first.id,
            selectedHostID: second.id
        )

        let decoded = try SharedHostStoreCodec.decode(SharedHostStoreCodec.encode(state))

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.hosts.map(\.id), [second.id, first.id])
    }

    func testSharedHostStoreCodecRetainsHostWithMalformedDisplayColorAsAutomatic() throws {
        let host = HostConfig(displayName: "DNS", address: "1.1.1.1")
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: SharedHostStoreCodec.encode(SharedHostStoreState(hosts: [host]))
            ) as? [String: Any]
        )
        var hosts = try XCTUnwrap(envelope["hosts"] as? [[String: Any]])
        hosts[0]["displayColor"] = ["red": "not-a-number", "green": 0.4, "blue": 0.8]
        envelope["hosts"] = hosts

        let decoded = try SharedHostStoreCodec.decode(JSONSerialization.data(withJSONObject: envelope))

        XCTAssertEqual(decoded.hosts, [host])
        XCTAssertNil(decoded.hosts.first?.displayColor)
    }

    func testSharedHostStoreCodecSkipsOnlyMalformedHostRecords() throws {
        let first = HostConfig(id: UUID(), displayName: "First", address: "1.1.1.1")
        let second = HostConfig(id: UUID(), displayName: "Second", address: "8.8.8.8")
        let state = SharedHostStoreState(hosts: [first, second], primaryHostID: first.id)
        let encoded = try SharedHostStoreCodec.encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var hosts = try XCTUnwrap(object["hosts"] as? [[String: Any]])
        hosts.insert(["id": "not-a-uuid", "displayName": 12], at: 1)
        object["hosts"] = hosts
        let partiallyCorrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let decoded = try SharedHostStoreCodec.decode(partiallyCorrupt)

        XCTAssertEqual(decoded.hosts, [first, second])
        XCTAssertEqual(decoded.primaryHostID, first.id)
    }

    func testSharedHostStoreCodecRoundTripsNonFiniteThresholds() throws {
        let values = [Double.nan, Double.infinity, -Double.infinity]
        for value in values {
            let host = HostConfig(
                displayName: "Edge \(String(describing: value))",
                address: "example.com",
                thresholds: LatencyThresholds(degradedMilliseconds: value, downAfterFailures: .max)
            )
            let decoded = try SharedHostStoreCodec.decode(
                SharedHostStoreCodec.encode(SharedHostStoreState(hosts: [host]))
            )
            let decodedValue = try XCTUnwrap(decoded.hosts.first?.thresholds.degradedMilliseconds)
            if value.isNaN {
                XCTAssertTrue(decodedValue.isNaN)
            } else {
                XCTAssertEqual(decodedValue, value)
            }
            XCTAssertEqual(decoded.hosts.first?.thresholds.downAfterFailures, .max)
        }
    }

    func testSharedHostStoreCodecRejectsMalformedJSONAndUnknownFutureVersion() throws {
        XCTAssertThrowsError(try SharedHostStoreCodec.decode(Data("not-json".utf8)))

        let current = try SharedHostStoreCodec.encode(SharedHostStoreState(hosts: [.defaultInternet]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["schemaVersion"] = SharedHostStoreCodec.currentSchemaVersion + 1
        let future = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try SharedHostStoreCodec.decode(future)) { error in
            XCTAssertEqual(error as? SharedHostStoreCodecError, .unsupportedSchemaVersion(2))
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "SharedHostStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}

private struct SharedHostStoreOverlapScenario: Sendable {
    let conflict = HostConfig(id: UUID(), displayName: "Conflict", address: "conflict.example")
    let receiverOnly = HostConfig(id: UUID(), displayName: "Receiver", address: "receiver.example")
    let localOnly = HostConfig(id: UUID(), displayName: "Local", address: "local.example")

    var receiverConflict: HostConfig {
        var host = conflict
        host.displayName = "Receiver Wins"
        host.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)
        return host
    }

    var localConflict: HostConfig {
        var host = conflict
        host.displayName = "Local Wins"
        host.notifications = .muted
        return host
    }

    var receiverEdited: HostConfig {
        var host = receiverOnly
        host.displayColor = HostDisplayColor(red: 0.72, green: 0.21, blue: 0.36)
        return host
    }

    var localEdited: HostConfig {
        var host = localOnly
        host.notifications = .muted
        return host
    }

    var initialState: SharedHostStoreState {
        SharedHostStoreState(hosts: [conflict, receiverOnly, localOnly])
    }

    var receiverState: SharedHostStoreState {
        SharedHostStoreState(
            hosts: [receiverConflict, receiverEdited, localOnly],
            primaryHostID: receiverOnly.id
        )
    }

    var localState: SharedHostStoreState {
        SharedHostStoreState(
            hosts: [localConflict, receiverOnly, localEdited],
            selectedHostID: localOnly.id
        )
    }

    var receiverWinsHosts: [HostConfig] {
        [receiverConflict, receiverEdited, localEdited]
    }

    var localWinsHosts: [HostConfig] {
        [localConflict, receiverEdited, localEdited]
    }
}

private actor SharedHostStoreOverlapGate {
    private var isBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func blockAfterLoad() async {
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
}
