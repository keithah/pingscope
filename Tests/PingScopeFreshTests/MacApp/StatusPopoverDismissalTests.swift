@testable import PingScope
import AppKit
import XCTest

/// Stands in for NSEvent's global monitor registry.
@MainActor
final class FakeGlobalMonitorRegistry {
    var handlers: [Int: (NSEvent) -> Void] = [:]
    var masks: [NSEvent.EventTypeMask] = []
    private var next = 0

    func makeMonitor() -> OutsideClickMonitor {
        OutsideClickMonitor(
            install: { mask, handler in
                self.next += 1
                self.masks.append(mask)
                self.handlers[self.next] = handler
                return self.next
            },
            remove: { token in
                self.handlers[token as! Int] = nil
            }
        )
    }

    func clickInAnotherApp() {
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
        handlers.values.forEach { $0(event) }
    }
}

@MainActor
final class StatusPopoverDismissalTests: XCTestCase {
    func testClickInAnotherAppReportsAnOutsideClick() {
        let registry = FakeGlobalMonitorRegistry()
        let monitor = registry.makeMonitor()
        var clicks = 0

        monitor.start { clicks += 1 }
        registry.clickInAnotherApp()

        XCTAssertEqual(clicks, 1)
        XCTAssertTrue(monitor.isMonitoring)
    }

    func testMonitorWatchesEveryMouseButton() {
        let registry = FakeGlobalMonitorRegistry()
        registry.makeMonitor().start {}

        XCTAssertEqual(registry.masks, [[.leftMouseDown, .rightMouseDown, .otherMouseDown]])
    }

    func testStoppedMonitorIsRemovedAndStaysQuiet() {
        let registry = FakeGlobalMonitorRegistry()
        let monitor = registry.makeMonitor()
        var clicks = 0

        monitor.start { clicks += 1 }
        monitor.stop()
        registry.clickInAnotherApp()

        XCTAssertEqual(clicks, 0)
        XCTAssertTrue(registry.handlers.isEmpty)
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testRestartingReplacesThePreviousMonitorInsteadOfStackingAnother() {
        let registry = FakeGlobalMonitorRegistry()
        let monitor = registry.makeMonitor()
        var first = 0, second = 0

        monitor.start { first += 1 }
        monitor.start { second += 1 }
        registry.clickInAnotherApp()

        XCTAssertEqual(registry.handlers.count, 1)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    func testStoppingTwiceIsHarmless() {
        let monitor = FakeGlobalMonitorRegistry().makeMonitor()

        monitor.start {}
        monitor.stop()
        monitor.stop()

        XCTAssertFalse(monitor.isMonitoring)
    }

    func testFocusReturnsWhenTheUserPutsThePopoverAway() {
        XCTAssertTrue(MenuBarPresentationMode.shouldReturnFocusAfterPopoverCloses(
            appIsActive: true, hasOtherVisibleWindow: false, closedByOutsideClick: false
        ))
    }

    func testFocusIsLeftAloneAfterAnOutsideClick() {
        XCTAssertFalse(MenuBarPresentationMode.shouldReturnFocusAfterPopoverCloses(
            appIsActive: true, hasOtherVisibleWindow: false, closedByOutsideClick: true
        ))
    }

    func testFocusStaysWithPingScopeWhenItOpenedAnotherWindow() {
        XCTAssertFalse(MenuBarPresentationMode.shouldReturnFocusAfterPopoverCloses(
            appIsActive: true, hasOtherVisibleWindow: true, closedByOutsideClick: false
        ))
    }

    func testFocusIsLeftAloneOnceAnotherAppIsAlreadyActive() {
        XCTAssertFalse(MenuBarPresentationMode.shouldReturnFocusAfterPopoverCloses(
            appIsActive: false, hasOtherVisibleWindow: false, closedByOutsideClick: false
        ))
    }
}

/// Drives a real NSPopover; only process-wide state is faked.
@MainActor
final class StatusPopoverControllerTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let registry = FakeGlobalMonitorRegistry()
        let anchorWindow: NSWindow
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 22))
        let otherApplication = NSWorkspace.shared.runningApplications.first { $0 != .current }
        var activations = 0
        var isActive = true
        var focusReturnedTo: [NSRunningApplication] = []
        var now: TimeInterval = 100
        var contentSize = NSSize(width: 200, height: 150)
        private(set) var controller: StatusPopoverController!

        init() {
            anchorWindow = NSWindow(
                contentRect: NSRect(x: 300, y: 500, width: 34, height: 22),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            anchorWindow.isReleasedWhenClosed = false
            anchorWindow.contentView = anchorView
            anchorWindow.orderFrontRegardless()

            var system = StatusPopoverController.System()
            system.frontmostApplication = { [unowned self] in otherApplication }
            system.activate = { [unowned self] in activations += 1 }
            system.isActive = { [unowned self] in isActive }
            system.returnFocus = { [unowned self] in focusReturnedTo.append($0) }
            system.uptime = { [unowned self] in now }
            controller = StatusPopoverController(
                system: system,
                outsideClickMonitor: registry.makeMonitor(),
                makeContent: {
                    let content = NSViewController()
                    content.view = NSView()
                    return content
                },
                contentSize: { [unowned self] _ in contentSize }
            )
            controller.animates = false
        }

        func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        func clickStatusItem() {
            controller.toggle(relativeTo: anchorView)
            settle()
        }

        func tearDown() {
            controller.close()
            settle()
            anchorWindow.close()
        }
    }

    func testOpeningTakesFocusAndStartsWatchingForClicksElsewhere() {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        fixture.clickStatusItem()

        XCTAssertTrue(fixture.controller.isShown)
        XCTAssertEqual(fixture.activations, 1, "an inactive app never hears about clicks outside its popover")
        XCTAssertEqual(fixture.registry.handlers.count, 1)
    }

    func testClickingInAnotherAppClosesThePopover() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.clickStatusItem()

        fixture.registry.clickInAnotherApp()
        fixture.settle()

        XCTAssertFalse(fixture.controller.isShown)
        XCTAssertTrue(fixture.registry.handlers.isEmpty, "the monitor must not outlive the popover")
    }

    func testClickingAwayLeavesFocusWhereverTheClickPutIt() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.clickStatusItem()

        fixture.registry.clickInAnotherApp()
        fixture.settle()

        XCTAssertTrue(fixture.focusReturnedTo.isEmpty)
    }

    func testClickingTheStatusItemAgainClosesThePopoverAndReturnsFocus() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.clickStatusItem()
        fixture.now += 5

        fixture.clickStatusItem()

        XCTAssertFalse(fixture.controller.isShown)
        XCTAssertNotNil(fixture.otherApplication)
        XCTAssertEqual(fixture.focusReturnedTo, [fixture.otherApplication].compactMap { $0 })
        XCTAssertTrue(fixture.registry.handlers.isEmpty)
    }

    func testFocusStaysWithPingScopeWhenThePopoverOpenedOneOfItsWindows() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.controller.hasOtherVisibleWindow = { true }
        fixture.clickStatusItem()

        fixture.controller.close()
        fixture.settle()

        XCTAssertFalse(fixture.controller.isShown)
        XCTAssertTrue(fixture.focusReturnedTo.isEmpty)
    }

    func testTheClickThatDismissedThePopoverDoesNotReopenIt() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.clickStatusItem()

        // The transient popover takes a click on the status item for an outside
        // click and closes; the same click then reaches the toggle.
        fixture.controller.close()
        fixture.settle()
        fixture.clickStatusItem()

        XCTAssertFalse(fixture.controller.isShown)
    }

    func testTheNextClickAfterADismissalOpensThePopover() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.clickStatusItem()
        fixture.controller.close()
        fixture.settle()
        fixture.now += MenuBarPresentationMode.popoverReopenSuppressionInterval

        fixture.clickStatusItem()

        XCTAssertTrue(fixture.controller.isShown)
        XCTAssertEqual(fixture.activations, 2)
    }

    func testEveryClickTogglesWhenClicksAreSpacedOut() {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        for expected in [true, false, true, false, true] {
            fixture.now += 1
            fixture.clickStatusItem()
            XCTAssertEqual(fixture.controller.isShown, expected)
        }
    }

    func testVisibilityChangesAreReportedOnOpenAndClose() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        var reported: [Bool] = []
        fixture.controller.onVisibilityChange = { reported.append(fixture.controller.isShown) }

        fixture.clickStatusItem()
        fixture.registry.clickInAnotherApp()
        fixture.settle()

        XCTAssertEqual(reported, [true, false])
    }

    func testAnOpenPopoverResizesAndAClosedOneIgnoresIt() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        var asked = 0

        fixture.controller.resize { _ in asked += 1; return NSSize(width: 200, height: 300) }
        XCTAssertEqual(asked, 0)

        fixture.clickStatusItem()
        fixture.controller.resize { _ in asked += 1; return NSSize(width: 200, height: 300) }
        fixture.settle()

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(fixture.controller.window?.contentViewController?.view.frame.height ?? 0, 300, accuracy: 0.5)
    }
}
