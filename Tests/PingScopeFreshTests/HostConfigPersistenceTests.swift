import XCTest
@testable import PingScope
import PingScopeCore

final class HostConfigPersistenceTests: XCTestCase {
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
