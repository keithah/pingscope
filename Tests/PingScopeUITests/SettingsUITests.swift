import XCTest

/// The Settings window: tab navigation and host management.
final class SettingsUITests: PingScopeUITestCase {
    private static let tabs: [(id: String, title: String)] = [
        ("hosts", "Hosts"),
        ("display", "Display"),
        ("notifications", "Notifications"),
        ("history", "History"),
        ("diagnostics", "Diagnostics"),
        ("advanced", "Advanced"),
        ("about", "About"),
    ]

    func testSettingsOpensOnHostsForFirstRun() throws {
        launchWindowed()
        let settings = openSettings()

        let title = settings.staticTexts["settings.header.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertEqual(text(of: title), "Hosts")
    }

    func testCommandCommaOpensSettings() throws {
        launchWindowed()

        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            app.windows["PingScope Settings"].waitForExistence(timeout: Self.uiTimeout),
            "⌘, did not open Settings"
        )
    }

    func testEverySettingsTabShowsItsPane() throws {
        launchWindowed()
        let settings = openSettings()
        let title = settings.staticTexts["settings.header.title"]

        for tab in Self.tabs {
            let button = settings.buttons["settings.tab.\(tab.id)"]
            XCTAssertTrue(button.waitForExistence(timeout: Self.uiTimeout), "Missing sidebar tab \(tab.id)")
            button.click()
            waitUntil("Header shows \(tab.title)") { [self] in text(of: title) == tab.title }
        }
        attachScreenshot(named: "settings-about")
    }

    func testAddingHostListsItInSettings() throws {
        launchWindowed()
        let settings = openSettings()

        let count = settings.staticTexts["settings.hosts.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.uiTimeout))
        let before = configuredCount(count)
        let rowsBefore = hostRows(in: settings).count

        addHost(named: "UITest Loopback", address: "127.0.0.1", in: settings)

        waitUntil("Configured count increments") { [self] in configuredCount(count) == before + 1 }
        waitUntil("A host row is added") { [self] in hostRows(in: settings).count == rowsBefore + 1 }
        XCTAssertTrue(settings.staticTexts["UITest Loopback"].firstMatch.waitForExistence(timeout: Self.uiTimeout))
        attachScreenshot(named: "settings-host-added")
    }

    /// Guards the isolation contract: a UI-test launch always starts from
    /// first-run defaults, so one test's changes never leak into the next.
    func testUITestLaunchesStartFromCleanDefaults() throws {
        launchWindowed()
        var settings = openSettings()
        let initialCount = configuredCount(settings.staticTexts["settings.hosts.count"])
        addHost(named: "UITest Leak Probe", address: "127.0.0.1", in: settings)
        XCTAssertTrue(settings.staticTexts["UITest Leak Probe"].firstMatch.waitForExistence(timeout: Self.uiTimeout))

        app.terminate()
        launchWindowed()
        settings = openSettings()

        let count = settings.staticTexts["settings.hosts.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertEqual(configuredCount(count), initialCount)
        XCTAssertFalse(settings.staticTexts["UITest Leak Probe"].firstMatch.exists)
    }

    // MARK: - Helpers

    private func addHost(named name: String, address: String, in settings: XCUIElement) {
        settings.buttons["settings.hosts.add"].click()

        let nameField = settings.textFields["settings.hostEditor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.uiTimeout))
        nameField.click()
        nameField.typeText(name)

        let addressField = settings.textFields["settings.hostEditor.address"]
        addressField.click()
        addressField.typeText(address)

        let save = settings.buttons["settings.hostEditor.save"]
        waitUntil("Save becomes enabled") { save.isEnabled }
        save.click()
    }

    private func hostRows(in settings: XCUIElement) -> XCUIElementQuery {
        settings.descendants(matching: .any).matching(identifier: "settings.hosts.row")
    }

    /// Parses "N configured".
    private func configuredCount(_ element: XCUIElement) -> Int {
        let words = text(of: element).split(separator: " ")
        return words.first.flatMap { Int($0) } ?? -1
    }
}
