import XCTest
@testable import PingScope

final class StatusItemTitleFormatterTests: XCTestCase {
    private let formatter = StatusItemTitleFormatter()

    func testCompactModeRemovesMillisecondsSuffix() {
        XCTAssertEqual(formatter.titleText(for: "48 ms", isCompactModeEnabled: true), "48")
    }

    func testCompactModeLeavesFallbackTextUntouched() {
        XCTAssertEqual(formatter.titleText(for: "N/A", isCompactModeEnabled: true), "N/A")
    }

    func testNonCompactModeKeepsFullDisplayText() {
        XCTAssertEqual(formatter.titleText(for: "48 ms", isCompactModeEnabled: false), "48 ms")
    }
}
