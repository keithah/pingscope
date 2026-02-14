import AppKit
import SwiftUI
import XCTest
@testable import PingMonitor

@MainActor
final class DisplayContentFactoryTests: XCTestCase {
    func testFactoryBuildsDisplayRootViewHostingControllerForFullMode() {
        let factory = makeFactory(suffix: "full")

        let viewController = factory.make(mode: .full, showsFloatingChrome: false)

        guard let hostingController = viewController as? NSHostingController<DisplayRootView> else {
            XCTFail("Expected NSHostingController<DisplayRootView>, got: \(type(of: viewController))")
            return
        }

        XCTAssertEqual(hostingController.rootView.mode, DisplayMode.full)
        XCTAssertFalse(hostingController.rootView.showsFloatingChrome)
    }

    func testFactoryBuildsDisplayRootViewHostingControllerForCompactModeWithFloatingChrome() {
        let factory = makeFactory(suffix: "compact-floating")

        let viewController = factory.make(mode: .compact, showsFloatingChrome: true)

        guard let hostingController = viewController as? NSHostingController<DisplayRootView> else {
            XCTFail("Expected NSHostingController<DisplayRootView>, got: \(type(of: viewController))")
            return
        }

        XCTAssertEqual(hostingController.rootView.mode, DisplayMode.compact)
        XCTAssertTrue(hostingController.rootView.showsFloatingChrome)
    }

    private func makeFactory(suffix: String) -> DisplayContentFactory {
        let suiteName = "DisplayContentFactoryTests-\(suffix)-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = DisplayPreferencesStore(userDefaults: userDefaults, keyPrefix: "test.display.content")
        let viewModel = DisplayViewModel(preferencesStore: store)
        return DisplayContentFactory(viewModel: viewModel)
    }
}
