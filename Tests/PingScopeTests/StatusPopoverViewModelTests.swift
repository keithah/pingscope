import XCTest
@testable import PingScope

@MainActor
final class StatusPopoverViewModelTests: XCTestCase {
    func testSectionsPrioritizeStatusThenQuickActions() {
        let viewModel = StatusPopoverViewModel(initialSnapshot: .placeholder)

        XCTAssertEqual(viewModel.sections, [.status, .quickActions])
        XCTAssertEqual(viewModel.quickActions.map(\.kind), [.refresh, .switchHost, .settings])
    }

    func testSnapshotFallsBackToNAForMissingDisplayData() {
        let snapshot = StatusPopoverViewModel.makeSnapshot(
            status: .gray,
            latencyText: " ",
            hostSummary: nil
        )

        XCTAssertEqual(snapshot.statusLabel, "No Data")
        XCTAssertEqual(snapshot.latencyText, "N/A")
        XCTAssertEqual(snapshot.hostSummary, "N/A")
    }

    func testActionCallbacksFireForQuickActions() {
        var refreshed = false
        var switchedHost = false
        var openedSettings = false

        let viewModel = StatusPopoverViewModel(
            initialSnapshot: .placeholder,
            onRefresh: { refreshed = true },
            onSwitchHost: { switchedHost = true },
            onOpenSettings: { openedSettings = true }
        )

        viewModel.perform(.refresh)
        viewModel.perform(.switchHost)
        viewModel.perform(.settings)

        XCTAssertTrue(refreshed)
        XCTAssertTrue(switchedHost)
        XCTAssertTrue(openedSettings)
    }
}
