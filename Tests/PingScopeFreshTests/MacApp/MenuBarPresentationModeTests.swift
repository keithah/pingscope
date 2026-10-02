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

    func testRecentSamplesClaimOnlyWholeRows() {
        let rowHeight = RecentSamplesLayout.rowHeight

        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: rowHeight * 5, sampleCount: 8), 5)
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: rowHeight * 5 + rowHeight - 1, sampleCount: 8), 5)
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: rowHeight * 6, sampleCount: 8), 6)
    }

    func testRecentSamplesKeepMinimumFootprintWhenSpaceOrSamplesAreShort() {
        let minimum = RecentSamplesLayout.minimumVisibleRows

        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: 0, sampleCount: 8), minimum)
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: 1_000, sampleCount: 0), minimum)
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: 1_000, sampleCount: 1), minimum)
    }

    func testRecentSamplesNeverClaimMoreRowsThanSamples() {
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: 1_000, sampleCount: 8), 8)
        XCTAssertEqual(RecentSamplesLayout.visibleRowCount(availableHeight: .infinity, sampleCount: 8), 8)
    }

    func testRecentSamplesIdealSizeIsTheMinimumSoTheScrollViewOnlyScrollsWhenItMust() {
        // A scroll view sizes its content by ideal height. If the ideal were
        // every row, the status content would scroll at sizes where showing
        // fewer rows fits.
        XCTAssertEqual(
            RecentSamplesLayout.visibleRowCount(availableHeight: nil, sampleCount: 8),
            RecentSamplesLayout.minimumVisibleRows
        )
    }

    func testStatusContentOpensAtDefaultSizeUntilHostRowsOutgrowIt() {
        for hostRowCount in 0...MenuBarPresentationMode.statusHostRowsFittingDefaultHeight {
            XCTAssertEqual(
                MenuBarPresentationMode.statusContentSize(hostRowCount: hostRowCount, availableHeight: 2_000),
                MenuBarPresentationMode.statusContentSize
            )
        }
    }

    func testStatusContentGrowsByOneRowHeightPerExtraHost() {
        let hostRowCount = MenuBarPresentationMode.statusHostRowsFittingDefaultHeight + 2
        let size = MenuBarPresentationMode.statusContentSize(hostRowCount: hostRowCount, availableHeight: 2_000)

        XCTAssertEqual(size.width, MenuBarPresentationMode.statusContentSize.width)
        XCTAssertEqual(
            size.height,
            MenuBarPresentationMode.statusContentSize.height + 2 * MenuBarPresentationMode.statusHostRowHeight
        )
    }

    func testStatusContentHeightStaysBetweenMinimumAndScreen() {
        XCTAssertEqual(MenuBarPresentationMode.statusContentSize(hostRowCount: 40, availableHeight: 800).height, 800)
        XCTAssertEqual(
            MenuBarPresentationMode.statusContentSize(hostRowCount: 0, availableHeight: 100).height,
            MenuBarPresentationMode.statusContentMinimumSize.height
        )
    }

    func testClickThatDismissedThePopoverDoesNotReopenIt() {
        let interval = MenuBarPresentationMode.popoverReopenSuppressionInterval

        XCTAssertTrue(MenuBarPresentationMode.shouldSuppressPopoverReopen(now: 100, lastWillClose: 100))
        XCTAssertTrue(MenuBarPresentationMode.shouldSuppressPopoverReopen(now: 100 + interval / 2, lastWillClose: 100))
        XCTAssertFalse(MenuBarPresentationMode.shouldSuppressPopoverReopen(now: 100 + interval, lastWillClose: 100))
        XCTAssertFalse(MenuBarPresentationMode.shouldSuppressPopoverReopen(now: 100, lastWillClose: nil))
    }

    func testControlClickOnStatusItemIsSecondaryClick() {
        XCTAssertTrue(MenuBarPresentationMode.isControlClick(type: .leftMouseDown, modifierFlags: [.control]))
        XCTAssertFalse(MenuBarPresentationMode.isControlClick(type: .leftMouseDown, modifierFlags: []))
        XCTAssertFalse(MenuBarPresentationMode.isControlClick(type: .leftMouseDown, modifierFlags: [.command]))
        XCTAssertFalse(MenuBarPresentationMode.isControlClick(type: nil, modifierFlags: [.control]))
    }

    @MainActor
    func testStatusItemGlyphLeavesClicksToTheStatusBarButton() {
        let view = MenuBarStatusView(frame: NSRect(x: 0, y: 0, width: 34, height: 22))

        XCTAssertNil(view.hitTest(NSPoint(x: 17, y: 11)))
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
