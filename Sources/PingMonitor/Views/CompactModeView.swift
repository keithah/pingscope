import SwiftUI

struct CompactModeView: View {
    @ObservedObject var viewModel: DisplayViewModel

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            // In compact, the graph should visibly shrink when the window is resized smaller.
            let graphHeight = max(72, min(150, totalHeight * 0.34))

            VStack(alignment: .leading, spacing: 10) {
                hostPicker
                graphSection(graphHeight: graphHeight)
                historySection
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                viewModel.setDisplayMode(.compact)
            }
        }
    }

    private var hostPicker: some View {
        Picker("Host", selection: hostSelectionBinding) {
            ForEach(viewModel.hosts) { host in
                Text(host.name)
                    .tag(Optional(host.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func graphSection(graphHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                title: "Graph",
                isExpanded: viewModel.modeState(for: .compact).graphVisible,
                toggle: { viewModel.setGraphVisible(!$0, for: .compact) }
            )

            if viewModel.modeState(for: .compact).graphVisible {
                DisplayGraphView(points: viewModel.selectedHostGraphPoints)
                    .frame(height: graphHeight)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                title: "Recent Results",
                isExpanded: viewModel.modeState(for: .compact).historyVisible,
                toggle: { viewModel.setHistoryVisible(!$0, for: .compact) }
            )

            if viewModel.modeState(for: .compact).historyVisible {
                RecentResultsListView(rows: viewModel.selectedHostRecentResults, maxVisibleRows: 6)
            }
        }
    }

    private var hostSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedHostID },
            set: { viewModel.selectHost(id: $0) }
        )
    }

    private func sectionHeader(title: String, isExpanded: Bool, toggle: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
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
    let defaults = UserDefaults(suiteName: "preview-compact-mode")!
    let store = DisplayPreferencesStore(userDefaults: defaults, keyPrefix: "preview.compact")
    let viewModel = DisplayViewModel(preferencesStore: store)

    let hosts = [
        Host(name: "Google", address: "8.8.8.8"),
        Host(name: "Cloudflare", address: "1.1.1.1")
    ]
    viewModel.setHosts(hosts)
    viewModel.selectHost(id: hosts[0].id)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-25), latencyMS: 46)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-15), latencyMS: 52)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-5), latencyMS: nil)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date(), latencyMS: 40)

    return CompactModeView(viewModel: viewModel)
}
