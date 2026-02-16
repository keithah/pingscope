import SwiftUI

struct CompactModeView: View {
    @ObservedObject var viewModel: DisplayViewModel
    var onToggleCompact: (() -> Void)?
    var onToggleStayOnTop: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var isCompactEnabled: Bool = false
    var isStayOnTopEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Host picker + gear
            HStack(spacing: 6) {
                Picker("", selection: hostSelectionBinding) {
                    ForEach(viewModel.hosts) { host in
                        Text(host.name)
                            .tag(Optional(host.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(minWidth: 88, maxWidth: .infinity, alignment: .leading)

                // Switch to full
                Button {
                    onToggleCompact?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Switch to Full")

                settingsMenu
            }

            sectionHeader(
                title: "Ping History",
                isExpanded: viewModel.modeState(for: .compact).graphVisible,
                onToggle: {
                    viewModel.toggleGraphVisible(for: .compact)
                },
                expandedHelp: "Hide graph",
                collapsedHelp: "Show graph",
                compact: true
            )

            if viewModel.modeState(for: .compact).graphVisible {
                CompactGraphView(points: viewModel.selectedHostGraphPoints)
                    .frame(height: 40)
            }

            sectionHeader(
                title: "Recent Results",
                isExpanded: viewModel.modeState(for: .compact).historyVisible,
                onToggle: {
                    viewModel.toggleHistoryVisible(for: .compact)
                },
                expandedHelp: "Hide results",
                collapsedHelp: "Show results",
                compact: true
            )

            if viewModel.modeState(for: .compact).historyVisible {
                RecentResultsListView(
                    rows: viewModel.selectedHostRecentResults,
                    maxVisibleRows: 4,
                    compact: true,
                    showHostName: false
                )
            }
        }
        // Match FullMode look-and-feel (control heights differ, so tune top slightly).
        .padding(.horizontal, 8)
        .padding(.bottom, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.setDisplayMode(.compact)
        }
    }

    private var hostSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedHostID },
            set: { viewModel.selectHost(id: $0) }
        )
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                onToggleCompact?()
            } label: {
                if isCompactEnabled {
                    Label("Compact Mode", systemImage: "checkmark")
                } else {
                    Text("Compact Mode")
                }
            }

            Button {
                onToggleStayOnTop?()
            } label: {
                if isStayOnTopEnabled {
                    Label("Stay on Top", systemImage: "checkmark")
                } else {
                    Text("Stay on Top")
                }
            }

            Divider()

            Button("Settings...") {
                onOpenSettings?()
            }

            Divider()

            Button("Quit") {
                onQuit?()
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(
        title: String,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        expandedHelp: String,
        collapsedHelp: String,
        compact: Bool
    ) -> some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font((compact ? Font.callout : .subheadline).weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12, alignment: .leading)

                Text(title)
                    .font((compact ? Font.callout : .subheadline).weight(.semibold))
                    .lineLimit(1)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .help(isExpanded ? expandedHelp : collapsedHelp)
    }
}

/// Simplified graph for compact mode - just a line with small dots
struct CompactGraphView: View {
    let points: [DisplayViewModel.GraphPoint]

    private let dotRadius: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            if points.isEmpty {
                emptyState
            } else {
                chart(in: proxy.size)
            }
        }
    }

    private var emptyState: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func chart(in size: CGSize) -> some View {
        let xBounds = dateBounds(points)
        let yBounds = latencyBounds(points)

        ZStack {
            // Line path
            linePath(in: size, xBounds: xBounds, yBounds: yBounds)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Simple dots (only if not too many)
            if points.count <= 40 {
                Canvas { context, _ in
                    for point in points {
                        let position = positionForPoint(point, in: size, xBounds: xBounds, yBounds: yBounds)

                        let dotRect = CGRect(
                            x: position.x - dotRadius,
                            y: position.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        context.fill(Circle().path(in: dotRect), with: .color(Color.accentColor))
                    }
                }
            }
        }
    }

    private func linePath(in size: CGSize, xBounds: ClosedRange<TimeInterval>, yBounds: ClosedRange<Double>) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let position = positionForPoint(point, in: size, xBounds: xBounds, yBounds: yBounds)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
    }

    private func positionForPoint(
        _ point: DisplayViewModel.GraphPoint,
        in size: CGSize,
        xBounds: ClosedRange<TimeInterval>,
        yBounds: ClosedRange<Double>
    ) -> CGPoint {
        let xRange = max(0.001, xBounds.upperBound - xBounds.lowerBound)
        let yRange = max(0.001, yBounds.upperBound - yBounds.lowerBound)

        let timestamp = point.timestamp.timeIntervalSinceReferenceDate
        let normalizedX = (timestamp - xBounds.lowerBound) / xRange
        let normalizedY = (point.latencyMS - yBounds.lowerBound) / yRange

        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)

        let padding: CGFloat = 4
        let drawWidth = size.width - padding * 2
        let drawHeight = size.height - padding * 2

        return CGPoint(
            x: padding + clampedX * drawWidth,
            y: padding + (1 - clampedY) * drawHeight
        )
    }

    private func dateBounds(_ points: [DisplayViewModel.GraphPoint]) -> ClosedRange<TimeInterval> {
        let values = points.map { $0.timestamp.timeIntervalSinceReferenceDate }
        guard let lower = values.min(), let upper = values.max() else {
            return 0 ... 1
        }

        if lower == upper {
            return (lower - 1) ... (upper + 1)
        }

        return lower ... upper
    }

    private func latencyBounds(_ points: [DisplayViewModel.GraphPoint]) -> ClosedRange<Double> {
        let values = points.map(\.latencyMS)
        guard let maxVal = values.max() else {
            return 0 ... 100
        }

        return 0 ... max(maxVal * 1.1, 50)
    }
}

#if DEBUG
struct CompactModeView_Previews: PreviewProvider {
    static var previews: some View {
        let defaults = UserDefaults(suiteName: "preview-compact-mode")!
        let store = DisplayPreferencesStore(userDefaults: defaults, keyPrefix: "preview.compact")
        let viewModel = DisplayViewModel(preferencesStore: store)

        let hosts = [
            Host(name: "Google", address: "8.8.8.8"),
            Host(name: "Cloudflare", address: "1.1.1.1")
        ]
        viewModel.setHosts(hosts)
        viewModel.selectHost(id: hosts[0].id)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-25), latencyMS: 9)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-20), latencyMS: 12)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-15), latencyMS: 150)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-10), latencyMS: 7)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-5), latencyMS: 10)
        viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date(), latencyMS: 11)

        return CompactModeView(viewModel: viewModel)
            .frame(width: 260, height: 340)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
