import Foundation
import XCTest
@testable import PingMonitor

final class DisplayPreferencesStoreTests: XCTestCase {
    func testDefaultsWhenPreferencesAreMissing() {
        let suiteName = "DisplayPreferencesStoreTests-defaults-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display")
        let preferences = store.loadPreferences()

        XCTAssertNil(preferences.shared.selectedHostID)
        XCTAssertEqual(preferences.shared.selectedTimeRange, .fiveMinutes)
        XCTAssertEqual(preferences.full, .default(for: .full))
        XCTAssertEqual(preferences.compact, .default(for: .compact))
    }

    func testSharedStatePersistsWithoutOverwritingModeState() {
        let suiteName = "DisplayPreferencesStoreTests-shared-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let selectedHostID = UUID()
        let fullState = DisplayModeState(
            graphVisible: false,
            historyVisible: true,
            frameData: .init(x: 12, y: 24, width: 640, height: 420)
        )

        let writer = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display")
        writer.setModeState(fullState, for: .full)
        writer.sharedState = DisplaySharedState(selectedHostID: selectedHostID, selectedTimeRange: .tenMinutes)

        let reader = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display")

        XCTAssertEqual(reader.sharedState.selectedHostID, selectedHostID)
        XCTAssertEqual(reader.sharedState.selectedTimeRange, .tenMinutes)
        XCTAssertEqual(reader.modeState(for: .full), fullState)
        XCTAssertEqual(reader.modeState(for: .compact), .default(for: .compact))
    }

    func testFullAndCompactModeStatePersistIndependently() {
        let suiteName = "DisplayPreferencesStoreTests-modes-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let fullState = DisplayModeState(
            graphVisible: false,
            historyVisible: true,
            frameData: .init(x: 5, y: 10, width: 500, height: 420)
        )
        let compactState = DisplayModeState(
            graphVisible: true,
            historyVisible: false,
            frameData: .init(x: 40, y: 60, width: 320, height: 240)
        )

        let writer = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display")
        writer.setModeState(fullState, for: .full)
        writer.setModeState(compactState, for: .compact)

        let reader = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display")
        XCTAssertEqual(reader.modeState(for: .full), fullState)
        XCTAssertEqual(reader.modeState(for: .compact), compactState)
    }

    private func makeIsolatedUserDefaults(suiteName: String) -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }
        return userDefaults
    }
}
