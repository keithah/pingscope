@testable import PingScope
import AppKit
import SwiftUI
import XCTest

@MainActor
final class SettingsLayoutTests: XCTestCase {
    private func size(of view: some View, proposedWidth: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: proposedWidth, height: 10_000))
    }

    func testSectionCardsFillThePaneWhateverTheyContain() {
        let narrow = size(of: SettingsSection("Narrow") { Text("x") }, proposedWidth: 440)
        let wide = size(of: SettingsSection("Wide") { Color.clear.frame(height: 10) }, proposedWidth: 440)

        XCTAssertEqual(narrow.width, 440, accuracy: 0.5)
        XCTAssertEqual(narrow.width, wide.width, accuracy: 0.5)
    }

    func testPermissionControlsSitOnOneLineWhenThereIsRoom() {
        let roomy = size(of: NotificationPermissionControls(state: .notDetermined), proposedWidth: 600)
        let buttonsOnly = size(of: Button("Request") {}, proposedWidth: 600)

        XCTAssertEqual(roomy.height, buttonsOnly.height, accuracy: 1)
    }

    func testPermissionControlsStackInsteadOfSqueezingInTheDefaultWindow() {
        // What the Permission row has left for its controls at the settings
        // window's default 700pt width with always-visible scroll bars.
        let available: CGFloat = 250
        let roomy = size(of: NotificationPermissionControls(state: .notDetermined), proposedWidth: 600)
        let tight = size(of: NotificationPermissionControls(state: .notDetermined), proposedWidth: available)

        XCTAssertGreaterThan(roomy.width, available, "if one line fits, this test is no longer exercising the fallback")
        XCTAssertLessThanOrEqual(tight.width, available)
        XCTAssertGreaterThan(tight.height, roomy.height)
    }

    func testPermissionControlsNeverShrinkBelowTheirNaturalSize() {
        // fixedSize keeps the label on one line and the button titles whole, so
        // starving the view of width must not make it any narrower.
        let tight = size(of: NotificationPermissionControls(state: .notDetermined), proposedWidth: 250)
        let starved = size(of: NotificationPermissionControls(state: .notDetermined), proposedWidth: 40)

        XCTAssertEqual(starved.width, tight.width, accuracy: 0.5)
        XCTAssertEqual(starved.height, tight.height, accuracy: 0.5)
    }

    private var threeBlocks: some View {
        WrappingHStack(spacing: 10, lineSpacing: 6) {
            ForEach(0..<3, id: \.self) { _ in Color.clear.frame(width: 100, height: 20) }
        }
    }

    func testWrappingRowStaysOnOneLineWhenEverythingFits() {
        let fitted = size(of: threeBlocks, proposedWidth: 320)

        XCTAssertEqual(fitted.width, 320, accuracy: 0.5)
        XCTAssertEqual(fitted.height, 20, accuracy: 0.5)
    }

    func testWrappingRowMovesWhatDoesNotFitToTheNextLine() {
        let fitted = size(of: threeBlocks, proposedWidth: 250)

        XCTAssertEqual(fitted.width, 210, accuracy: 0.5)
        XCTAssertEqual(fitted.height, 46, accuracy: 0.5)
    }

    func testWrappingRowNeverSqueezesAChildThatIsWiderThanTheRow() {
        let fitted = size(of: threeBlocks, proposedWidth: 60)

        XCTAssertEqual(fitted.width, 100, accuracy: 0.5)
        XCTAssertEqual(fitted.height, 72, accuracy: 0.5)
    }

    func testWrappingRowKeepsButtonTitlesWholeInATightRow() {
        let natural = size(of: Button("Copy Summary") {}, proposedWidth: 1_000)
        let row = WrappingHStack {
            Button("Reveal Log") {}
            Button("Copy Summary") {}
            Button("Clear Log") {}
        }

        let tight = size(of: row, proposedWidth: 250)

        XCTAssertLessThanOrEqual(tight.width, 250)
        XCTAssertGreaterThanOrEqual(tight.width, natural.width)
        XCTAssertGreaterThan(tight.height, natural.height)
    }
}
