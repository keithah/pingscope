import SwiftUI

struct FullModeView: View {
    @ObservedObject var viewModel: DisplayViewModel

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            // Scale graph with window size while keeping it usable.
            let graphHeight = max(80, min(220, totalHeight * 0.34))

            VStack(alignment: .leading, spacing: 12) {
                hostPills
                graphSection(graphHeight: graphHeight)
                historySection
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                viewModel.setDisplayMode(.full)
            }
        }
    }

    private var hostPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.hosts) { host in
                    let isSelected = viewModel.selectedHostID == host.id

                    Button(host.name) {
                        viewModel.selectHost(id: host.id)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func graphSection(graphHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Graph",
                isExpanded: viewModel.modeState(for: .full).graphVisible,
                toggle: { viewModel.setGraphVisible(!$0, for: .full) }
            )

            if viewModel.modeState(for: .full).graphVisible {
                DisplayGraphView(points: viewModel.selectedHostGraphPoints)
                    .frame(height: graphHeight)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Recent Results",
                isExpanded: viewModel.modeState(for: .full).historyVisible,
                toggle: { viewModel.setHistoryVisible(!$0, for: .full) }
            )

            if viewModel.modeState(for: .full).historyVisible {
                RecentResultsListView(rows: viewModel.selectedHostRecentResults)
            }
        }
    }

    private func sectionHeader(title: String, isExpanded: Bool, toggle: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()

            Button {
                toggle(isExpanded)
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview-full-mode")!
    let store = DisplayPreferencesStore(userDefaults: defaults, keyPrefix: "preview.full")
    let viewModel = DisplayViewModel(preferencesStore: store)

    let hosts = [
        Host(name: "Google", address: "8.8.8.8"),
        Host(name: "Cloudflare", address: "1.1.1.1")
    ]
    viewModel.setHosts(hosts)
    viewModel.selectHost(id: hosts[0].id)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-20), latencyMS: 42)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-10), latencyMS: 49)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date(), latencyMS: 37)

    return FullModeView(viewModel: viewModel)
}
