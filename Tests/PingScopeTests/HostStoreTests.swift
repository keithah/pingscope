import Foundation
import XCTest
@testable import PingScope

final class HostStoreTests: XCTestCase {
    func testAddAcceptsICMPHostWithZeroPort() async {
        let suiteName = "HostStoreTests-add-icmp-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HostStore(defaults: defaults)
        let host = Host(name: "ICMP Add", address: "icmp-add.local", port: 0, pingMethod: .icmp)

        await store.add(host)

        let savedHosts = await store.hosts
        XCTAssertTrue(savedHosts.contains(host), "ICMP host with port 0 should be persisted")
    }

    func testUpdateAcceptsICMPHostWithZeroPort() async {
        let suiteName = "HostStoreTests-update-icmp-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HostStore(defaults: defaults)
        let original = Host(name: "ICMP Original", address: "icmp-old.local", port: 0, pingMethod: .icmp)
        await store.add(original)

        let updated = Host(
            id: original.id,
            name: "ICMP Updated",
            address: "icmp-new.local",
            port: 0,
            pingMethod: .icmp
        )
        await store.update(updated)

        let savedHosts = await store.hosts
        XCTAssertTrue(savedHosts.contains(updated), "Updated ICMP host with port 0 should remain persisted")
        XCTAssertFalse(savedHosts.contains(original), "ICMP host should be replaced during update")
    }

    func testNonICMPHostWithZeroPortIsRejectedForAddAndUpdate() async {
        let suiteName = "HostStoreTests-reject-non-icmp-zero-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HostStore(defaults: defaults)
        let invalidNewHost = Host(name: "TCP Invalid", address: "tcp-invalid.local", port: 0, pingMethod: .tcp)

        await store.add(invalidNewHost)

        let baseline = Host(name: "TCP Baseline", address: "tcp-valid.local", port: 443, pingMethod: .tcp)
        await store.add(baseline)

        let invalidUpdate = Host(
            id: baseline.id,
            name: "TCP Invalid Update",
            address: "tcp-valid.local",
            port: 0,
            pingMethod: .tcp
        )
        await store.update(invalidUpdate)

        let savedHosts = await store.hosts
        XCTAssertFalse(savedHosts.contains(invalidNewHost), "New non-ICMP host with port 0 should be rejected")
        XCTAssertTrue(savedHosts.contains(baseline), "Invalid update should not replace existing valid host")
        XCTAssertFalse(savedHosts.contains(invalidUpdate), "Updated non-ICMP host with port 0 should be rejected")
    }

    func testValidNonICMPHostStillPersists() async {
        let suiteName = "HostStoreTests-keep-non-icmp-valid-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HostStore(defaults: defaults)
        let host = Host(name: "UDP Host", address: "udp.local", port: 53, pingMethod: .udp)

        await store.add(host)

        let savedHosts = await store.hosts
        XCTAssertTrue(savedHosts.contains(host), "Valid non-ICMP host should continue persisting")
    }

    private func makeIsolatedUserDefaults(suiteName: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }
        return defaults
    }
}
