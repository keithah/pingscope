import AppKit
import PingScopeCore
import SwiftUI

enum PingScopeShareGraphScope: String, CaseIterable, Identifiable {
    case currentView
    case singleHost
    case allHosts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentView: "Current view"
        case .singleHost: "Single host"
        case .allHosts: "All hosts"
        }
    }
}

enum PingScopeShareGraphAppearance: String, CaseIterable, Identifiable {
    case current
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: "Current"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    var resolvedColorScheme: ColorScheme {
        switch self {
        case .current:
            return Self.resolvedColorScheme(for: NSApp.effectiveAppearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func resolvedColorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

struct PingScopeShareGraphOptions {
    var scope: PingScopeShareGraphScope = .currentView
    var range: TimeRange = .fiveMinutes
    var appearance: PingScopeShareGraphAppearance = .current
    var includesTable = false
}

struct PingScopeShareSampleRow: Identifiable {
    let id: UUID
    let timestamp: Date
    let hostName: String?
    let resultText: String
    let statusText: String
    let isSuccess: Bool
}

struct PingScopeShareGraphPresentation {
    let range: TimeRange
    let title: String
    let subtitle: String
    let statusText: String
    let statusColor: StatusColor
    let generatedAt: Date
    let showsAllHosts: Bool
    let colorScheme: ColorScheme
    let includesTable: Bool
    let sampleRows: [PingScopeShareSampleRow]
    let displayPresentation: PingScopeDisplayPresentation
}

struct PingScopeShareGraphImage: View {
    let presentation: PingScopeShareGraphPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            graph
                .frame(height: presentation.includesTable ? 250 : 310)
            stats
            if presentation.includesTable {
                sampleTable
            }
            footer
        }
        .padding(32)
        .frame(width: 920, height: presentation.includesTable ? 720 : 560)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        )
        .environment(\.colorScheme, presentation.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PingScope")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(presentation.title)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(presentation.subtitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 24)
            VStack(alignment: .trailing, spacing: 10) {
                Text(presentation.range.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.secondary.opacity(0.14), in: Capsule())
                Label(presentation.statusText, systemImage: "circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(statusColor: presentation.statusColor))
            }
        }
    }

    @ViewBuilder
    private var graph: some View {
        if presentation.showsAllHosts {
            MultiHostLatencyGraph(
                series: presentation.displayPresentation.allHostGraphSeries,
                graphData: presentation.displayPresentation.allHostsGraphData,
                showsAxes: true
            )
        } else {
            LatencyGraph(
                graphData: presentation.displayPresentation.primaryGraphData,
                showsAxes: true
            )
        }
    }

    private var stats: some View {
        let stats = presentation.displayPresentation.primaryStats
        return HStack(spacing: 26) {
            shareStat("TX", "\(stats.transmitted)")
            shareStat("RX", "\(stats.received)")
            shareStat("Loss", "\(Int(stats.lossPercent.rounded()))%")
            shareStat("Min", latency(stats.minimumMilliseconds))
            shareStat("Avg", latency(stats.averageMilliseconds))
            shareStat("Max", latency(stats.maximumMilliseconds))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sampleTable: some View {
        VStack(spacing: 0) {
            sampleTableHeader
            ForEach(presentation.sampleRows) { row in
                sampleTableRow(row)
            }
            if presentation.sampleRows.isEmpty {
                Text("No samples in the last \(presentation.range.rawValue).")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sampleTableHeader: some View {
        HStack(spacing: 14) {
            Text("Time").frame(width: 120, alignment: .leading)
            if presentation.showsAllHosts {
                Text("Host").frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Result").frame(width: 130, alignment: .leading)
            Text("Status").frame(width: 110, alignment: .leading)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(.secondary.opacity(0.08))
    }

    private func sampleTableRow(_ row: PingScopeShareSampleRow) -> some View {
        HStack(spacing: 14) {
            Text(row.timestamp, style: .time)
                .frame(width: 120, alignment: .leading)
            if presentation.showsAllHosts {
                Text(row.hostName ?? "Unknown")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(row.resultText)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            Text(row.statusText)
                .foregroundStyle(row.isSuccess ? Color.primary : Color.red)
                .frame(width: 110, alignment: .leading)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(row.isSuccess ? Color.clear : Color.red.opacity(0.08))
    }

    private func shareStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .frame(minWidth: 74, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("Generated \(presentation.generatedAt, style: .date) at \(presentation.generatedAt, style: .time)")
            Spacer()
            Text("PingScope")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func latency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))ms"
    }
}

enum PingScopeShareGraphRenderer {
    @MainActor
    static func image(for presentation: PingScopeShareGraphPresentation) -> NSImage? {
        let renderer = ImageRenderer(content: PingScopeShareGraphImage(presentation: presentation))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}
