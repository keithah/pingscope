import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

#if os(iOS)
public struct PingScopeIOSHistoryView: View {
    public let hostName: String
    public let selectedRange: HistoryRange
    public let requestedLens: HistoryLens
    public let selectedMapLens: HistoryMapLens
    public let decision: PingScopeIOSHistoryContainerDecision
    public let mapContent: AnyView
    public let onSelectRange: (HistoryRange) -> Void
    public let onSelectLens: (HistoryLens) -> Void
    public let onSelectMapLens: (HistoryMapLens) -> Void
    public let onRequestMapPermission: () -> Void
    public let onShare: (HistoryExportFormat) -> Void
    public let onShareReport: (HistoryReportFormat) -> Void

    public init(
        hostName: String,
        selectedRange: HistoryRange,
        requestedLens: HistoryLens,
        selectedMapLens: HistoryMapLens,
        decision: PingScopeIOSHistoryContainerDecision,
        mapContent: AnyView = AnyView(EmptyView()),
        onSelectRange: @escaping (HistoryRange) -> Void,
        onSelectLens: @escaping (HistoryLens) -> Void,
        onSelectMapLens: @escaping (HistoryMapLens) -> Void,
        onRequestMapPermission: @escaping () -> Void,
        onShare: @escaping (HistoryExportFormat) -> Void,
        onShareReport: @escaping (HistoryReportFormat) -> Void
    ) {
        self.hostName = hostName
        self.selectedRange = selectedRange
        self.requestedLens = requestedLens
        self.selectedMapLens = selectedMapLens
        self.decision = decision
        self.mapContent = mapContent
        self.onSelectRange = onSelectRange
        self.onSelectLens = onSelectLens
        self.onSelectMapLens = onSelectMapLens
        self.onRequestMapPermission = onRequestMapPermission
        self.onShare = onShare
        self.onShareReport = onShareReport
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            HistoryRangeControl(selectedRange: selectedRange, onSelectRange: onSelectRange)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if decision.isMapAvailable {
                HistoryLensControl(selectedLens: decision.effectiveLens, onSelectLens: onSelectLens)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            if decision.showsContextualPermissionPrompt {
                permissionPrompt
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            Group {
                switch decision.effectiveLens {
                case .chart:
                    PingScopeIOSHistoryChartView(
                        selectedRange: selectedRange,
                        resolvedPresentation: decision.resolvedPresentation
                    )
                case .map:
                    mapContent
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("History")
                    .font(.largeTitle.bold())
                Text(hostName)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Menu {
                Section("Report Card") {
                    ForEach(HistoryReportFormat.allCases) { format in
                        Button(format.displayName) {
                            onShareReport(format)
                        }
                    }
                }
                Section("Data") {
                ForEach(HistoryExportFormat.allCases) { format in
                    Button(format.displayName) {
                        onShare(format)
                    }
                }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share History")
            .accessibilityHint("Choose report card or data format")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var permissionPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Map your connection history")
                    .font(.subheadline.weight(.semibold))
                Text("Tag future samples with an approximate location while monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Enable") {
                onRequestMapPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Enable History map location")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HistoryRangeControl: View {
    let selectedRange: HistoryRange
    let onSelectRange: (HistoryRange) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases, id: \.self) { range in
                Button {
                    onSelectRange(range)
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedRange == range ? Color(.tertiarySystemBackground) : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History range")
    }
}

private struct HistoryLensControl: View {
    let selectedLens: HistoryLens
    let onSelectLens: (HistoryLens) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(HistoryLens.allCases, id: \.self) { lens in
                Button {
                    onSelectLens(lens)
                } label: {
                    Label(lens == .chart ? "Chart" : "Map", systemImage: lens == .chart ? "chart.xyaxis.line" : "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedLens == lens ? Color(.tertiarySystemBackground) : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedLens == lens ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History view")
    }
}
#endif
