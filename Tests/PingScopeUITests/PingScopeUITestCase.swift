import XCTest

/// Base class for PingScope UI tests.
///
/// Every launch sets `PINGSCOPE_UI_TESTING=1`, which makes a DEBUG build of the
/// app use a throwaway defaults suite (wiped at launch), a temporary history
/// database, its own single-instance lock, and no iCloud sync or Sparkle
/// updater. Tests therefore start from first-run state and never touch the
/// developer's installed PingScope data. See `UITestingEnvironment.swift`.
@MainActor
class PingScopeUITestCase: XCTestCase {
    static let launchTimeout: TimeInterval = 20
    static let uiTimeout: TimeInterval = 10

    private(set) var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PINGSCOPE_UI_TESTING"] = "1"
        // Never restore windows from a previous (possibly crashed) run.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    }

    override func tearDown() async throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
        app = nil
        try await super.tearDown()
    }

    /// Launches with the menu-bar content in a regular window (`-windowed`).
    /// The window hosts the same `StatusPopoverView` as the status-item
    /// popover, so it exercises identical UI without depending on the menu
    /// bar having room for the status item.
    @discardableResult
    func launchWindowed() -> XCUIElement {
        app.launchArguments.append("-windowed")
        app.launch()
        let window = app.windows["PingScope"]
        XCTAssertTrue(
            window.waitForExistence(timeout: Self.launchTimeout),
            "The windowed status interface did not appear"
        )
        XCTAssertTrue(
            window.buttons["popover.openHistory"].waitForExistence(timeout: Self.uiTimeout),
            "The status content did not render in the window"
        )
        // macOS may refuse the app's own activation request at launch and keep
        // another app frontmost; key presses and menus then misbehave.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.uiTimeout), "PingScope did not come to the front")
        return window
    }

    /// Launches as a menu bar accessory, exactly as users run the app.
    func launchAsMenuBarApp() {
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningBackground, timeout: Self.launchTimeout)
                || app.wait(for: .runningForeground, timeout: 1),
            "PingScope did not finish launching"
        )
    }

    /// Opens Settings from the status content's gear menu and returns its
    /// window. Clicks, unlike key presses, reach the app even when macOS keeps
    /// another app frontmost, so this is the path tests build on; ⌘, has its
    /// own test.
    @discardableResult
    func openSettings(from statusWindow: XCUIElement? = nil) -> XCUIElement {
        let root = statusWindow ?? app.windows["PingScope"]
        let gear = root.descendants(matching: .any)["popover.settingsMenu"].firstMatch
        let item = app.menuItems["Open Settings"]
        gear.click()
        if !item.waitForExistence(timeout: 3) {
            // A first click can be spent focusing the window.
            gear.click()
        }
        XCTAssertTrue(item.waitForExistence(timeout: Self.uiTimeout), "Settings menu did not open")
        item.click()
        let window = app.windows["PingScope Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.uiTimeout), "Settings window did not open")
        return window
    }

    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: @escaping () -> Bool
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        expectation.expectationDescription = description
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, description)
    }

    /// The visible text of a static text element. SwiftUI on macOS puts it in
    /// `value`, AppKit in `label`; read whichever is set.
    func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
