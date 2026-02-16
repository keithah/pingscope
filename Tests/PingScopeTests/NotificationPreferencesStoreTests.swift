import Foundation
import XCTest
@testable import PingScope

final class NotificationPreferencesStoreTests: XCTestCase {
    func testHostOverrideStateDefaultsToInheritedGlobalSettings() {
        let suiteName = "NotificationPreferencesStoreTests-default-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let hostID = UUID()
        let store = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")

        let state = store.hostOverrideState(for: hostID)

        XCTAssertEqual(state.hostID, hostID)
        XCTAssertFalse(state.isUsingOverride)
        XCTAssertTrue(state.notificationsEnabled)
        XCTAssertNil(state.enabledAlertTypes)
        XCTAssertNil(store.hostOverride(for: hostID))
    }

    func testSaveHostOverrideStatePersistsAcrossStoreInstances() {
        let suiteName = "NotificationPreferencesStoreTests-save-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let hostID = UUID()
        let expectedTypes: Set<AlertType> = [.highLatency, .recovery]
        let writer = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")

        writer.saveHostOverrideState(
            HostNotificationOverrideState(
                hostID: hostID,
                isUsingOverride: true,
                notificationsEnabled: false,
                enabledAlertTypes: expectedTypes
            )
        )

        let reader = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")
        let state = reader.hostOverrideState(for: hostID)

        XCTAssertTrue(state.isUsingOverride)
        XCTAssertFalse(state.notificationsEnabled)
        XCTAssertEqual(state.enabledAlertTypes, expectedTypes)

        let persistedOverride = reader.hostOverride(for: hostID)
        XCTAssertEqual(persistedOverride?.hostID, hostID)
        XCTAssertEqual(persistedOverride?.enabled, false)
        XCTAssertEqual(persistedOverride?.enabledAlertTypes, expectedTypes)
    }

    func testClearHostOverrideRemovesPersistedOverride() {
        let suiteName = "NotificationPreferencesStoreTests-clear-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let hostID = UUID()
        let writer = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")
        writer.setHostOverride(
            HostNotificationOverride(
                hostID: hostID,
                enabled: false,
                enabledAlertTypes: [.noResponse]
            )
        )

        writer.clearHostOverride(for: hostID)

        let reader = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")
        let state = reader.hostOverrideState(for: hostID)
        XCTAssertNil(reader.hostOverride(for: hostID))
        XCTAssertFalse(state.isUsingOverride)
        XCTAssertTrue(state.notificationsEnabled)
        XCTAssertNil(state.enabledAlertTypes)
    }

    func testSaveHostOverrideStateWithInheritedModeClearsExistingOverride() {
        let suiteName = "NotificationPreferencesStoreTests-inherit-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let hostID = UUID()
        let writer = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")
        writer.setHostOverride(
            HostNotificationOverride(
                hostID: hostID,
                enabled: false,
                enabledAlertTypes: [.intermittent]
            )
        )

        writer.saveHostOverrideState(
            HostNotificationOverrideState(
                hostID: hostID,
                isUsingOverride: false,
                notificationsEnabled: false,
                enabledAlertTypes: [.intermittent]
            )
        )

        let reader = NotificationPreferencesStore(userDefaults: userDefaults, key: "test.notifications")
        XCTAssertNil(reader.hostOverride(for: hostID))
        XCTAssertEqual(reader.hostOverrideState(for: hostID), HostNotificationOverrideState(
            hostID: hostID,
            isUsingOverride: false,
            notificationsEnabled: true,
            enabledAlertTypes: nil
        ))
    }

    private func makeIsolatedUserDefaults(suiteName: String) -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }
        return userDefaults
    }
}
