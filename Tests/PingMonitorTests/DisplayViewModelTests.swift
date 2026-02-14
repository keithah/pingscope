import Foundation
import XCTest
@testable import PingMonitor

@MainActor
final class DisplayViewModelTests: XCTestCase {
    func testSwitchingModeDoesNotResetSelectedHost() {
        let suiteName = "DisplayViewModelTests-host-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.vm")
        let viewModel = DisplayViewModel(preferencesStore: store)
        let hosts = makeHosts()

        viewModel.setHosts(hosts)
        viewModel.selectHost(id: hosts[1].id)
        viewModel.setDisplayMode(.compact)
        viewModel.setDisplayMode(.full)

        XCTAssertEqual(viewModel.selectedHostID, hosts[1].id)
    }

    func testSwitchingModeDoesNotResetSelectedTimeRange() {
        let suiteName = "DisplayViewModelTests-range-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.vm")
        let viewModel = DisplayViewModel(preferencesStore: store)

        viewModel.setTimeRange(.oneHour)
        viewModel.setDisplayMode(.compact)
        viewModel.setDisplayMode(.full)

        XCTAssertEqual(viewModel.selectedTimeRange, .oneHour)
    }

    func testPanelVisibilityMemoryIsIsolatedPerMode() {
        let suiteName = "DisplayViewModelTests-panels-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.vm")
        let viewModel = DisplayViewModel(preferencesStore: store)

        viewModel.setDisplayMode(.full)
        viewModel.setGraphVisible(false)
        viewModel.setHistoryVisible(true)

        viewModel.setDisplayMode(.compact)
        viewModel.setGraphVisible(true)
        viewModel.setHistoryVisible(false)

        XCTAssertEqual(viewModel.modeState(for: .full).graphVisible, false)
        XCTAssertEqual(viewModel.modeState(for: .full).historyVisible, true)
        XCTAssertEqual(viewModel.modeState(for: .compact).graphVisible, true)
        XCTAssertEqual(viewModel.modeState(for: .compact).historyVisible, false)
    }

    func testRecentProjectionKeepsNewestOrderAndUsesBoundedMemory() {
        let suiteName = "DisplayViewModelTests-recent-\(UUID().uuidString)"
        let userDefaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.vm")
        let viewModel = DisplayViewModel(preferencesStore: store, sampleBufferLimit: 8)
        let host = PingMonitor.Host(name: "Google", address: "8.8.8.8")

        viewModel.setHosts([host])
        viewModel.selectHost(id: host.id)
        viewModel.setTimeRange(.oneHour)

        let base = Date().addingTimeInterval(-120)
        for sampleIndex in 0 ..< 12 {
            let timestamp = base.addingTimeInterval(TimeInterval(sampleIndex))
            viewModel.ingestSample(hostID: host.id, timestamp: timestamp, latencyMS: Double(sampleIndex))
        }

        let bounded = viewModel.recentResults(for: host.id, limit: 20)
        let compactWindow = viewModel.recentResults(for: host.id, limit: 6)

        XCTAssertEqual(bounded.count, 8)
        XCTAssertEqual(compactWindow.count, 6)
        XCTAssertEqual(compactWindow.first?.latencyMS, 11)
        XCTAssertEqual(compactWindow.last?.latencyMS, 6)
    }

    private func makeHosts() -> [PingMonitor.Host] {
        [
            PingMonitor.Host(name: "Google", address: "8.8.8.8"),
            PingMonitor.Host(name: "Cloudflare", address: "1.1.1.1")
        ]
    }

    private func makeIsolatedUserDefaults(suiteName: String) -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }

        return userDefaults
    }
}
