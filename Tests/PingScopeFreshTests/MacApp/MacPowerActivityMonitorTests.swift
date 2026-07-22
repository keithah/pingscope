import XCTest
@testable import PingScope
@testable import PingScopeCore

final class MacPowerActivityMonitorTests: XCTestCase {
    @MainActor
    func testDisplayWakeDoesNotClearAnIndependentScreenLock() {
        var reported: [CadenceInputs] = []
        let monitor = MacPowerActivityMonitor { reported.append($0) }
        monitor.start()

        monitor.screenDidLock()
        monitor.screenDidSleep()
        monitor.screenDidWake()

        XCTAssertEqual(reported.last?.visibility, .background)
    }

    func testCadenceVisibilityTracksSettingsAndHistoryWindows() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/PingScopeApp/PingScopeApp.swift"),
            encoding: .utf8
        )
        let settingsStart = try XCTUnwrap(source.range(of: "func openSettings()"))
        let historyStart = try XCTUnwrap(source.range(of: "func openHistory()"))
        let showOverlayStart = try XCTUnwrap(source.range(of: "func showOverlay()"))
        let settings = source[settingsStart.lowerBound..<historyStart.lowerBound]
        let history = source[historyStart.lowerBound..<showOverlayStart.lowerBound]
        let updateStart = try XCTUnwrap(source.range(of: "private func updatePowerMonitorUIVisibility()"))
        let updateEnd = try XCTUnwrap(
            source.range(
                of: "private func showContextMenu(",
                range: updateStart.upperBound..<source.endIndex
            )
        )
        let update = source[updateStart.lowerBound..<updateEnd.lowerBound]

        XCTAssertTrue(settings.contains("window.delegate = self"))
        XCTAssertTrue(history.contains("window.delegate = self"))
        XCTAssertTrue(settings.contains("updatePowerMonitorUIVisibility()"))
        XCTAssertTrue(history.contains("updatePowerMonitorUIVisibility()"))
        XCTAssertTrue(update.contains("settingsWindowController?.window?.isVisible == true"))
        XCTAssertTrue(update.contains("historyWindowController?.window?.isVisible == true"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
