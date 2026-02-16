import AppKit
import XCTest
@testable import PingScope

@MainActor
final class DisplayModeCoordinatorTests: XCTestCase {
    func testAnchoredAndClampedFrameStaysWithinVisibleScreenBounds() {
        let anchorRect = NSRect(x: 385, y: 290, width: 20, height: 18)
        let preferredFrame = NSRect(x: 0, y: 0, width: 280, height: 220)
        let visibleFrame = NSRect(x: 100, y: 100, width: 300, height: 400)

        let frame = DisplayModeCoordinator.anchoredAndClampedFrame(
            anchorRect: anchorRect,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame,
            minimumSize: NSSize(width: 280, height: 220)
        )

        XCTAssertEqual(frame.origin.x, 120)
        XCTAssertEqual(frame.origin.y, 100)
        XCTAssertEqual(frame.width, 280)
        XCTAssertEqual(frame.height, 220)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testAnchoredAndClampedFrameAppliesMinimumSizeFloor() {
        let anchorRect = NSRect(x: 385, y: 290, width: 20, height: 18)
        let preferredFrame = NSRect(x: 0, y: 0, width: 32, height: 44)
        let visibleFrame = NSRect(x: 0, y: 0, width: 2_000, height: 1_200)

        let frame = DisplayModeCoordinator.anchoredAndClampedFrame(
            anchorRect: anchorRect,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame,
            minimumSize: NSSize(width: 280, height: 220)
        )

        XCTAssertEqual(frame.size.width, 280)
        XCTAssertEqual(frame.size.height, 220)
    }

    func testFloatingWindowUsesBorderlessFloatingCurrentSpaceConfiguration() {
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: makePreferencesStore(suffix: "window-flags"))
        let window = coordinator.makeFloatingWindow(frame: NSRect(x: 20, y: 30, width: 280, height: 220))

        XCTAssertTrue(window.styleMask.contains(.borderless))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testStandardWindowUsesChromelessMovableFixedSizeConfiguration() {
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: makePreferencesStore(suffix: "standard-window-flags"))
        let window = coordinator.makeStandardWindow(frame: NSRect(x: 20, y: 30, width: 450, height: 500))

        XCTAssertTrue(window.styleMask.contains(.borderless))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testStandardWindowPersistsUserResizedFramePerMode() {
        _ = NSApplication.shared

        let store = makePreferencesStore(suffix: "standard-window-resize-persistence")
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: store)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        addTeardownBlock {
            NSStatusBar.system.removeStatusItem(statusItem)
            coordinator.closeAll()
        }

        guard let button = statusItem.button else {
            XCTFail("Status item button missing")
            return
        }

        let contentViewController = NSViewController()
        coordinator.showStandardWindow(from: button, mode: .full, contentViewController: contentViewController)

        guard let window = coordinator.standardWindow else {
            XCTFail("Expected standard window to be created")
            return
        }

        let fullResized = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: 520,
            height: 560
        )
        window.setFrame(fullResized, display: false)
        coordinator.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))

        XCTAssertEqual(store.modeState(for: .full).frameData.width, 520, accuracy: 0.5)
        XCTAssertEqual(store.modeState(for: .full).frameData.height, 560, accuracy: 0.5)

        coordinator.showStandardWindow(from: button, mode: .compact, contentViewController: contentViewController)
        let compactResized = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: 340,
            height: 260
        )
        window.setFrame(compactResized, display: false)
        coordinator.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))

        XCTAssertEqual(store.modeState(for: .compact).frameData.width, 340, accuracy: 0.5)
        XCTAssertEqual(store.modeState(for: .compact).frameData.height, 260, accuracy: 0.5)

        coordinator.closeStandardWindow()
        coordinator.showStandardWindow(from: button, mode: .full, contentViewController: contentViewController)

        guard let reopened = coordinator.standardWindow else {
            XCTFail("Expected standard window to still exist")
            return
        }

        XCTAssertEqual(reopened.frame.size.width, CGFloat(520), accuracy: CGFloat(0.5))
        XCTAssertEqual(reopened.frame.size.height, CGFloat(560), accuracy: CGFloat(0.5))
    }

    func testSwitchingShellsPreservesCurrentWindowSizeForSameMode() {
        _ = NSApplication.shared

        let store = makePreferencesStore(suffix: "shell-switch-preserves-size")
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: store)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        addTeardownBlock {
            NSStatusBar.system.removeStatusItem(statusItem)
            coordinator.closeAll()
        }

        guard let button = statusItem.button else {
            XCTFail("Status item button missing")
            return
        }

        let contentViewController = NSViewController()
        coordinator.showStandardWindow(from: button, mode: .full, contentViewController: contentViewController)

        guard let window = coordinator.standardWindow else {
            XCTFail("Expected standard window to be created")
            return
        }

        let resized = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: 620,
            height: 700
        )
        window.setFrame(resized, display: false)
        coordinator.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))

        coordinator.showFloatingWindow(from: button, mode: .full, contentViewController: contentViewController)
        guard let floating = coordinator.floatingWindow else {
            XCTFail("Expected floating window to be created")
            return
        }

        XCTAssertEqual(floating.frame.size.width, CGFloat(620), accuracy: CGFloat(0.5))
        XCTAssertEqual(floating.frame.size.height, CGFloat(700), accuracy: CGFloat(0.5))
    }

    func testFloatingWindowEnforcesPerModeMinimumContentSize() {
        _ = NSApplication.shared

        let store = makePreferencesStore(suffix: "floating-min-size")
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: store)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        addTeardownBlock {
            NSStatusBar.system.removeStatusItem(statusItem)
            coordinator.closeAll()
        }

        guard let button = statusItem.button else {
            XCTFail("Status item button missing")
            return
        }

        let contentViewController = NSViewController()
        coordinator.showFloatingWindow(from: button, mode: .compact, contentViewController: contentViewController)

        guard let floating = coordinator.floatingWindow else {
            XCTFail("Expected floating window to be created")
            return
        }

        XCTAssertEqual(floating.contentMinSize.width, 150, accuracy: 0.5)
        XCTAssertEqual(floating.contentMinSize.height, 80, accuracy: 0.5)
        // We allow resizing larger, but never below the per-mode minimum.
        XCTAssertTrue(floating.styleMask.contains(.resizable))
    }

    func testDragHandleMouseDownUsesDedicatedDragPath() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))

        let handle = DragHandleNSView(frame: NSRect(x: 0, y: 0, width: 64, height: 20))
        window.contentView?.addSubview(handle)

        var dragInvoked = false
        handle.dragPerformer = { _, _ in
            dragInvoked = true
        }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 8, y: 8),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        XCTAssertNotNil(event)
        guard let event else {
            return
        }

        handle.mouseDown(with: event)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(dragInvoked)
    }

    private func makePreferencesStore(suffix: String) -> DisplayPreferencesStore {
        let suiteName = "DisplayModeCoordinatorTests-\(suffix)-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        return DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.coordinator")
    }
}
