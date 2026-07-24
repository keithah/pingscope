@testable import PingScope
import AppKit
import XCTest

final class MenuBarPresentationModeTests: XCTestCase {
    @MainActor
    func testSettingsAndHistoryWindowsStayOpenAndShareTabbingGroup() {
        let settings = NSWindow()
        let history = NSWindow()

        PingScopePrimaryWindowConfiguration.apply(to: settings)
        PingScopePrimaryWindowConfiguration.apply(to: history)

        for window in [settings, history] {
            XCTAssertFalse(window.isReleasedWhenClosed)
            XCTAssertFalse(window.hidesOnDeactivate)
            XCTAssertEqual(window.tabbingMode, .preferred)
            XCTAssertTrue(window.styleMask.contains(.resizable))
        }
        XCTAssertEqual(settings.tabbingIdentifier, history.tabbingIdentifier)
        XCTAssertFalse(settings.tabbingIdentifier.isEmpty)
    }

    func testMenuPopoverAllowsUserInitiatedDetach() {
        XCTAssertTrue(MenuBarPresentationMode.shouldAllowUserDetachForMenuPopover())
    }

    func testDetachedPopoverWindowHasTrafficLightsAndResize() {
        let style = MenuBarPresentationMode.detachedPopoverWindowStyleMask

        XCTAssertTrue(style.contains(.titled))
        XCTAssertTrue(style.contains(.closable))
        XCTAssertTrue(style.contains(.miniaturizable))
        XCTAssertTrue(style.contains(.resizable))
    }

    @MainActor
    func testOverlayWindowUsesHiddenTitlebarResizeStyle() {
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 96))

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertGreaterThanOrEqual(window.minSize.width, 150)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 54)
    }

    @MainActor
    func testCompactOverlayWindowAllowsIndependentHorizontalAndVerticalResize() {
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 80))
        window.aspectRatio = NSSize(width: 2, height: 1)
        window.contentAspectRatio = NSSize(width: 2, height: 1)

        window.enableFreeformResize()

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.aspectRatio, .zero)
        XCTAssertEqual(window.contentAspectRatio, .zero)
        XCTAssertEqual(window.resizeIncrements.width, 1)
        XCTAssertEqual(window.resizeIncrements.height, 1)
    }

    func testDetachedPopoverContentHasSmallerMinimumThanInitialSize() {
        XCTAssertLessThan(MenuBarPresentationMode.statusContentMinimumSize.width, MenuBarPresentationMode.statusContentSize.width)
        XCTAssertLessThan(MenuBarPresentationMode.statusContentMinimumSize.height, MenuBarPresentationMode.statusContentSize.height)
    }

    func testStatusPopoverUsesAccessibleControlAndGraphSizes() {
        XCTAssertGreaterThanOrEqual(MenuBarPresentationMode.statusControlHitSize, 40)
        XCTAssertGreaterThanOrEqual(MenuBarPresentationMode.statusGraphMinimumHeight, 150)
    }

    func testRecentSamplesTableColumnsFitWithinStatusContentMinimumWidthWithoutHorizontalOverflow() {
        // The status content view pads on each side; the table's column
        // minimums must fit inside what remains at the window's declared
        // minimum width, or the Table shows a permanent horizontal scrollbar
        // whenever the window is narrowed toward that minimum.
        let horizontalContentPadding = MenuBarPresentationMode.statusContentPadding * 2
        let availableWidth = MenuBarPresentationMode.statusContentMinimumSize.width - horizontalContentPadding

        XCTAssertLessThanOrEqual(RecentSamplesColumnLayout.totalMinimumWidth, availableWidth)
    }

    func testPingIntervalOptionsIncludeReadableSlowerChoices() {
        XCTAssertEqual(PingIntervalPresentation.options.map(\.label), ["1s", "2s", "5s", "10s", "30s"])
        XCTAssertEqual(PingIntervalPresentation.options.map(\.milliseconds), [1_000, 2_000, 5_000, 10_000, 30_000])
    }

    func testPingIntervalOptionsIncludeCurrentCustomValue() {
        let options = PingIntervalPresentation.options(including: 3_000)

        XCTAssertEqual(options.map(\.milliseconds), [1_000, 2_000, 5_000, 10_000, 30_000, 3_000])
        XCTAssertEqual(options.last?.label, "3s")
    }

    func testPingIntervalSelectionPreservesNonPresetValue() {
        XCTAssertEqual(PingIntervalPresentation.selection(for: .milliseconds(3_000)), 3_000)
    }
}
