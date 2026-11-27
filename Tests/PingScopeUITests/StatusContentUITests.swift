import XCTest

/// The menu-bar content: status item, popover, and the controls in its header.
final class StatusContentUITests: PingScopeUITestCase {
    func testStatusItemIsExposedToAccessibility() throws {
        launchAsMenuBarApp()

        let statusItem = app.descendants(matching: .any)["pingscope.statusItem"].firstMatch
        XCTAssertTrue(
            statusItem.waitForExistence(timeout: Self.uiTimeout),
            "The status item lost its accessibility identifier; automation cannot find it"
        )
        XCTAssertEqual(statusItem.label, "PingScope")
    }

    func testClickingStatusItemTogglesPopover() throws {
        launchAsMenuBarApp()

        let statusItem = app.descendants(matching: .any)["pingscope.statusItem"].firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: Self.uiTimeout))
        guard statusItem.isHittable else {
            // A crowded menu bar (or the notch) can hide the item; the status
            // content itself is still covered by the windowed tests below.
            throw XCTSkip("The PingScope status item is not visible in this menu bar")
        }
        XCTAssertEqual(statusItem.value as? String, "closed")

        // The popover window of an accessory app is not reachable from the
        // app's accessibility root, so the status item reports its state.
        statusItem.click()
        waitUntil("Popover opens") { statusItem.value as? String == "open" }
        attachScreenshot(named: "status-popover")

        statusItem.click()
        waitUntil("Popover closes") { statusItem.value as? String == "closed" }
    }

    func testStatusContentShowsHeaderControls() throws {
        let window = launchWindowed()

        XCTAssertTrue(window.buttons["popover.openHistory"].exists)
        XCTAssertTrue(window.buttons["popover.shareGraph"].exists)
        XCTAssertTrue(window.descendants(matching: .any)["popover.settingsMenu"].firstMatch.exists)
        XCTAssertTrue(window.descendants(matching: .any)["popover.hostChip"].firstMatch.exists)
        attachScreenshot(named: "status-content")
    }

    func testHistoryButtonOpensHistoryWindow() throws {
        let window = launchWindowed()

        window.buttons["popover.openHistory"].click()

        let history = app.windows["PingScope History"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.uiTimeout), "History window did not open")
        XCTAssertTrue(
            history.descendants(matching: .any)["history.rangePicker"].firstMatch.waitForExistence(timeout: Self.uiTimeout),
            "History window is missing its range picker"
        )
        attachScreenshot(named: "history-window")
    }

    func testSettingsMenuOpensSettings() throws {
        let window = launchWindowed()

        window.descendants(matching: .any)["popover.settingsMenu"].firstMatch.click()
        let openSettings = app.menuItems["Open Settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: Self.uiTimeout), "Settings menu did not open")
        XCTAssertTrue(app.menuItems["Open History"].exists)
        XCTAssertTrue(app.menuItems["Quit PingScope"].exists)
        openSettings.click()

        XCTAssertTrue(
            app.windows["PingScope Settings"].waitForExistence(timeout: Self.uiTimeout),
            "Open Settings did not open the Settings window"
        )
    }
}
