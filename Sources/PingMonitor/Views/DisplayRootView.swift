import SwiftUI

struct DisplayRootView: View {
    @ObservedObject var viewModel: DisplayViewModel
    let mode: DisplayMode
    let showsFloatingChrome: Bool

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if showsFloatingChrome {
                floatingHeader
            }

            modeView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelShape.fill(Color(nsColor: .windowBackgroundColor)))
        .clipShape(panelShape)
        .overlay(panelShape.strokeBorder(Color.black.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var modeView: some View {
        switch mode {
        case .full:
            FullModeView(viewModel: viewModel)
        case .compact:
            CompactModeView(viewModel: viewModel)
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        .padding(.bottom, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }
}
