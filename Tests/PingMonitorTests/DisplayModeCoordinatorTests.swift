import AppKit
import XCTest
@testable import PingMonitor

@MainActor
final class DisplayModeCoordinatorTests: XCTestCase {
    func testAnchoredAndClampedFrameStaysWithinVisibleScreenBounds() {
        let anchorRect = NSRect(x: 385, y: 290, width: 20, height: 18)
        let preferredFrame = NSRect(x: 0, y: 0, width: 280, height: 220)
        let visibleFrame = NSRect(x: 100, y: 100, width: 300, height: 200)

        let frame = DisplayModeCoordinator.anchoredAndClampedFrame(
            anchorRect: anchorRect,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.origin.x, 120)
        XCTAssertEqual(frame.origin.y, 100)
        XCTAssertEqual(frame.width, 280)
        XCTAssertEqual(frame.height, 200)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testFloatingWindowUsesBorderlessFloatingCurrentSpaceConfiguration() {
        let coordinator = DisplayModeCoordinator(displayPreferencesStore: makePreferencesStore(suffix: "window-flags"))
        let window = coordinator.makeFloatingWindow(frame: NSRect(x: 20, y: 30, width: 280, height: 220))

        XCTAssertEqual(window.styleMask, [.borderless])
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

        XCTAssertEqual(window.styleMask, [.borderless])
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
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
