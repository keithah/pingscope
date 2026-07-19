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
}
