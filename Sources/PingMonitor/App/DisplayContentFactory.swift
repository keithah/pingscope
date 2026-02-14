import AppKit
import SwiftUI

@MainActor
struct DisplayContentFactory {
    let viewModel: DisplayViewModel

    func make(mode: DisplayMode, showsFloatingChrome: Bool) -> NSViewController {
        let rootView = DisplayRootView(
            viewModel: viewModel,
            mode: mode,
            showsFloatingChrome: showsFloatingChrome
        )
        return NSHostingController(rootView: rootView)
    }
}
