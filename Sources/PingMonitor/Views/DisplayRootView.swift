import SwiftUI

struct DisplayRootView: View {
    @ObservedObject var viewModel: DisplayViewModel
    let mode: DisplayMode
    let showsFloatingChrome: Bool
    var menuActions: DisplayMenuActions = DisplayMenuActions()

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if showsFloatingChrome {
                floatingHeader
            }

            modeView
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

    private var floatingHeader: some View {
        Color.clear
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .background(WindowDragHandleView())
    }
}
