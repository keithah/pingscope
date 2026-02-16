import SwiftUI

struct DisplayRootView: View {
    @ObservedObject var viewModel: DisplayViewModel
    let mode: DisplayMode
    let showsFloatingChrome: Bool
    var menuActions: DisplayMenuActions = DisplayMenuActions()

    private let cornerRadius: CGFloat = 14

    var body: some View {
        modeView
            // Provide a small drag region at the top without shifting content down.
            // Both Full and Compact views use top padding >= 12, so this won't overlap controls.
            .overlay(alignment: .top) {
                if showsFloatingChrome {
                    WindowDragHandleView()
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                }
            }
        .frame(minWidth: mode == .full ? 350 : 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(panelShape.fill(Color(nsColor: .windowBackgroundColor)))
        .clipShape(panelShape)
        .overlay(panelShape.strokeBorder(Color.black.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var modeView: some View {
        switch mode {
        case .full:
            FullModeView(
                viewModel: viewModel,
                onToggleCompact: menuActions.onToggleCompact,
                onToggleStayOnTop: menuActions.onToggleStayOnTop,
                onOpenSettings: menuActions.onOpenSettings,
                onQuit: menuActions.onQuit,
                isCompactEnabled: menuActions.isCompactEnabled,
                isStayOnTopEnabled: menuActions.isStayOnTopEnabled
            )
        case .compact:
            CompactModeView(
                viewModel: viewModel,
                onToggleCompact: menuActions.onToggleCompact,
                onToggleStayOnTop: menuActions.onToggleStayOnTop,
                onOpenSettings: menuActions.onOpenSettings,
                onQuit: menuActions.onQuit,
                isCompactEnabled: menuActions.isCompactEnabled,
                isStayOnTopEnabled: menuActions.isStayOnTopEnabled
            )
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // NOTE: floating chrome is implemented as an overlay; no header spacer needed.
}
