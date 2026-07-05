@testable import PingScope
import AppKit
import XCTest

final class MenuBarPresentationModeTests: XCTestCase {
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

    func testDetachedPopoverContentHasSmallerMinimumThanInitialSize() {
        XCTAssertLessThan(MenuBarPresentationMode.statusContentMinimumSize.width, MenuBarPresentationMode.statusContentSize.width)
        XCTAssertLessThan(MenuBarPresentationMode.statusContentMinimumSize.height, MenuBarPresentationMode.statusContentSize.height)
    }

    func testStatusPopoverUsesAccessibleControlAndGraphSizes() {
        XCTAssertGreaterThanOrEqual(MenuBarPresentationMode.statusControlHitSize, 40)
        XCTAssertGreaterThanOrEqual(MenuBarPresentationMode.statusGraphMinimumHeight, 150)
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
