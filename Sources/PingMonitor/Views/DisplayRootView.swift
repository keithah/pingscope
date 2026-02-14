import SwiftUI

struct DisplayRootView: View {
    @ObservedObject var viewModel: DisplayViewModel
    let mode: DisplayMode
    let showsFloatingChrome: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsFloatingChrome {
                floatingHeader
            }

            switch mode {
            case .full:
                FullModeView(viewModel: viewModel)
            case .compact:
                CompactModeView(viewModel: viewModel)
            }
        }
    }

    private var floatingHeader: some View {
        HStack(spacing: 8) {
            WindowDragHandleView()
                .frame(width: 68, height: 20)

            Spacer()

            Text(mode == .compact ? "Compact" : "Full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
