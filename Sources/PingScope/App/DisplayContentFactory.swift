import AppKit
import SwiftUI

struct DisplayMenuActions {
    var onToggleCompact: () -> Void = {}
    var onToggleStayOnTop: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var isCompactEnabled: Bool = false
    var isStayOnTopEnabled: Bool = false
}

@MainActor
struct DisplayContentFactory {
    let viewModel: DisplayViewModel
    var menuActions: DisplayMenuActions = DisplayMenuActions()

    func make(mode: DisplayMode, showsFloatingChrome: Bool) -> NSViewController {
        let rootView = DisplayRootView(
            viewModel: viewModel,
            mode: mode,
            showsFloatingChrome: showsFloatingChrome,
            menuActions: menuActions
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.intrinsicContentSize]
        return hostingController
    }
}
