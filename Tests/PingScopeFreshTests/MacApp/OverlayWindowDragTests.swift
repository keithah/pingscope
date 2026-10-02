@testable import PingScope
import AppKit
import SwiftUI
import XCTest

@MainActor
final class OverlayWindowDragTests: XCTestCase {
    private final class Spy {
        var graphClicks = 0
        var contentTaps = 0
    }

    /// Tall enough to leave a band of plain SwiftUI content between the AppKit
    /// graph click area (bottom 42%) and the hidden title bar.
    private let contentSize = NSSize(width: 300, height: 200)
    private let graphPoint = NSPoint(x: 150, y: 40)
    private let contentPoint = NSPoint(x: 100, y: 115)

    private func makeOverlay(_ spy: Spy) -> OverlayWindow {
        let window = OverlayWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 300), size: contentSize))
        window.isReleasedWhenClosed = false
        window.contentView = OverlayContainerView(
            rootView: Color.clear.contentShape(Rectangle()).onTapGesture { spy.contentTaps += 1 },
            isCompact: { false },
            hostOptions: { [] },
            onToggleCompact: {},
            onDetails: { spy.graphClicks += 1 },
            onSettings: {},
            onClose: {},
            onSelectHost: { _ in },
            onSelectAllHosts: {},
            showsAllHosts: { false },
            showsLegend: { false },
            onToggleLegend: {}
        )
        window.setFrameOrigin(NSPoint(x: 200, y: 300))
        // Mouse events are only routed to views of a window that is on screen.
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    /// Presses at `point`, moves the pointer by each offset in turn, releases.
    private func press(at point: NSPoint, in window: OverlayWindow, movingBy offsets: [NSPoint]) {
        let start = NSPoint(x: 1_000, y: 1_000)
        var pointer = start
        window.mouseLocation = { pointer }
        func send(_ type: NSEvent.EventType) {
            guard let event = NSEvent.mouseEvent(
                with: type,
                // The window follows the pointer, so the location inside it holds still.
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ) else {
                XCTFail("could not synthesize \(type)")
                return
            }
            window.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        send(.leftMouseDown)
        for offset in offsets {
            pointer = NSPoint(x: start.x + offset.x, y: start.y + offset.y)
            send(.leftMouseDragged)
        }
        send(.leftMouseUp)
    }

    func testDraggingTheGraphAreaMovesTheOverlayWithThePointer() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: graphPoint, in: window, movingBy: [NSPoint(x: 10, y: -5), NSPoint(x: 60, y: -40)])

        XCTAssertEqual(window.frame.origin, NSPoint(x: 260, y: 260))
    }

    func testDraggingSwiftUIContentMovesTheOverlayToo() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: contentPoint, in: window, movingBy: [NSPoint(x: -30, y: 25)])

        XCTAssertEqual(window.frame.origin, NSPoint(x: 170, y: 325))
    }

    func testFinishingADragIsNotAClick() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: graphPoint, in: window, movingBy: [NSPoint(x: 40, y: 0)])
        press(at: contentPoint, in: window, movingBy: [NSPoint(x: 0, y: 40)])

        XCTAssertEqual(spy.graphClicks, 0)
        XCTAssertEqual(spy.contentTaps, 0)
    }

    func testAPlainClickStillReachesTheContentAndDoesNotMoveTheOverlay() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: graphPoint, in: window, movingBy: [])
        press(at: contentPoint, in: window, movingBy: [])

        XCTAssertEqual(spy.graphClicks, 1)
        XCTAssertEqual(spy.contentTaps, 1)
        XCTAssertEqual(window.frame.origin, NSPoint(x: 200, y: 300))
    }

    func testClicksStillWorkAfterADrag() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: contentPoint, in: window, movingBy: [NSPoint(x: 40, y: 0)])
        press(at: contentPoint, in: window, movingBy: [])
        press(at: graphPoint, in: window, movingBy: [])

        XCTAssertEqual(spy.contentTaps, 1)
        XCTAssertEqual(spy.graphClicks, 1)
    }

    func testAJitteryClickBelowTheThresholdIsStillAClick() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }
        let jitter = OverlayWindow.dragThreshold - 1

        press(at: graphPoint, in: window, movingBy: [NSPoint(x: jitter, y: 0)])

        XCTAssertEqual(window.frame.origin, NSPoint(x: 200, y: 300))
        XCTAssertEqual(spy.graphClicks, 1)
    }

    func testOnceDraggingTheOverlayFollowsThePointerBackInsideTheThreshold() {
        let spy = Spy()
        let window = makeOverlay(spy)
        defer { window.close() }

        press(at: graphPoint, in: window, movingBy: [NSPoint(x: 50, y: 0), NSPoint(x: 1, y: 0)])

        XCTAssertEqual(window.frame.origin, NSPoint(x: 201, y: 300))
        XCTAssertEqual(spy.graphClicks, 0)
    }
}
