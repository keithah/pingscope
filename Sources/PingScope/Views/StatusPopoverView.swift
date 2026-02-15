import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var viewModel: StatusPopoverViewModel
    @ObservedObject var hostListViewModel: HostListViewModel

    init(viewModel: StatusPopoverViewModel, hostListViewModel: HostListViewModel? = nil) {
        self.viewModel = viewModel
        self.hostListViewModel = hostListViewModel ?? HostListViewModel(onSelectHost: { _ in })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.networkChangeIndicator {
                networkChangeBanner
            }

            statusSection
            Divider()
            hostsSection
            Divider()
            quickActionsSection
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 340)
    }

    private var statusSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.snapshot.statusLabel)
                    .font(.headline)
                Text(viewModel.snapshot.latencyText)
                    .font(.title3.weight(.semibold))
                Text(viewModel.snapshot.hostSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(viewModel.quickActions) { action in
                Button(action.title) {
                    viewModel.perform(action.kind)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hostsSection: some View {
        HostListView(viewModel: hostListViewModel)
            .frame(height: 220)
    }

    private var networkChangeBanner: some View {
        Label("Network changed", systemImage: "network")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
    }

    private var statusColor: Color {
        switch viewModel.snapshot.statusCategory {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .gray:
            return .gray
        }
    }
}

#Preview {
    StatusPopoverView(
        viewModel: StatusPopoverViewModel(
            initialSnapshot: .init(
                statusLabel: "Healthy",
                statusCategory: .green,
                latencyText: "41 ms",
                hostSummary: "Google DNS (8.8.8.8)"
            )
        )
    )
}
