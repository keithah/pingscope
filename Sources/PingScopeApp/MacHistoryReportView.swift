import AppKit
import PingScopeCore
import PingScopeHistoryKit
import SwiftUI
import UniformTypeIdentifiers

struct MacHistoryReportSheet: View {
    let report: HistoryReportPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("History Report").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            ScrollView(.vertical) {
                MacHistoryReportPreview(presentation: report)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                    .padding(16)
            }
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save PNG…") { save() }
                    .accessibilityIdentifier("history.reportSaveButton")
                Button("Share…") { share() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("history.reportShareButton")
            }
        }
        .padding(18)
        .frame(minWidth: 800, minHeight: 650)
    }

    private func save() {
        guard let data = MacHistoryReportRenderer.pngData(for: report) else {
            message = "Could not render the report"
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save PingScope History Report"
        panel.nameFieldStringValue = "\(Self.safeFilename(report.hostName))-\(report.rangeLabel.lowercased())-report.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try data.write(to: destination, options: .atomic)
            message = "Saved \(destination.lastPathComponent)"
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }

    private func share() {
        guard let image = MacHistoryReportRenderer.image(for: report) else {
            message = "Could not render the report"
            return
        }
        guard let sourceView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            message = "Report copied to the clipboard"
            return
        }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    private static func safeFilename(_ value: String) -> String {
        let safe = value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(safe).split(separator: "-").joined(separator: "-")
    }
}

private struct MacHistoryReportPreview: View {
    let presentation: HistoryReportPresentation

    var body: some View {
        GeometryReader { geometry in
            let previewSize = MacHistoryReportRenderer.previewSize(
                fittingWidth: min(geometry.size.width, MacHistoryReportRenderer.size.width)
            )
            MacHistoryReportCard(presentation: presentation)
                .frame(
                    width: MacHistoryReportRenderer.size.width,
                    height: MacHistoryReportRenderer.size.height
                )
                .scaleEffect(
                    previewSize.width / MacHistoryReportRenderer.size.width,
                    anchor: .topLeading
                )
        }
        .aspectRatio(
            MacHistoryReportRenderer.size.width / MacHistoryReportRenderer.size.height,
            contentMode: .fit
        )
    }
}

struct MacHistoryReportCard: View {
    let presentation: HistoryReportPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVERAGE").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(latency(presentation.averageMilliseconds))
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                }
                Spacer()
                Text("\(presentation.sampleCount) samples")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            reportChart.frame(height: 150)
            metricStrip
            HStack(alignment: .top, spacing: 18) {
                networkHighlights.frame(maxWidth: .infinity, alignment: .topLeading)
                sessionHighlights.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(36)
        .foregroundStyle(Color.primary)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.reportCard")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.brand)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Text("NETWORK HISTORY REPORT")
                    .font(.caption.bold().monospaced()).tracking(1.4).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(presentation.hostName).font(.title3.bold().monospaced()).lineLimit(1)
                Text(presentation.rangeLabel).font(.headline.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var reportChart: some View {
        Canvas { context, size in
            let graph = presentation.graphPresentation
            let dates = graph.averageLineSegments.flatMap { $0 }.map(\.timestamp)
            guard let start = dates.min(), let end = dates.max() else { return }
            let span = max(end.timeIntervalSince(start), 1)
            let maximum = max(graph.scale.axisMaximumMilliseconds, 1)
            for segment in graph.averageLineSegments {
                let points = segment.map { point in
                    CGPoint(
                        x: size.width * point.timestamp.timeIntervalSince(start) / span,
                        y: size.height * (1 - point.latencyMilliseconds / maximum)
                    )
                }
                if points.count > 1 {
                    context.stroke(
                        Path(LatencyCurve.smoothedPath(points: points, closed: false)),
                        with: .linearGradient(
                            Gradient(colors: [.blue, .cyan]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var metricStrip: some View {
        HStack(spacing: 10) {
            metric("MIN", latency(presentation.minimumMilliseconds))
            metric("P95", latency(presentation.p95Milliseconds))
            metric("MAX", latency(presentation.maximumMilliseconds))
            metric("LOSS", percentage(presentation.lossPercent))
            metric("UPTIME", percentage(presentation.uptimePercent))
        }
    }

    private var networkHighlights: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY NETWORK").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(presentation.networkPresentation.cards.prefix(4)) { card in
                HStack(spacing: 7) {
                    Image(systemName: card.systemImage).frame(width: 16).foregroundStyle(.blue)
                    Text(card.label).lineLimit(1)
                    if card.hasVPN { Text("VPN").font(.caption2.bold()).foregroundStyle(.purple) }
                    Spacer()
                    Text("\(card.uptimeText) uptime").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var sessionHighlights: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SESSIONS").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(Array(presentation.sessions.suffix(4).enumerated()), id: \.offset) { _, session in
                HStack(spacing: 7) {
                    Circle().fill(Color(statusColor: session.status.statusColor)).frame(width: 7, height: 7)
                    Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Text("\(session.samples.count) samples").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func latency(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) ms" } ?? "--"
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
    }
}

enum MacHistoryReportRenderer {
    static let size = CGSize(width: 900, height: 750)

    static func previewSize(fittingWidth width: CGFloat) -> CGSize {
        let width = max(width, 0)
        return CGSize(width: width, height: width * size.height / size.width)
    }

    @MainActor
    static func image(for presentation: HistoryReportPresentation) -> NSImage? {
        let renderer = ImageRenderer(
            content: MacHistoryReportCard(presentation: presentation)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    @MainActor
    static func pngData(for presentation: HistoryReportPresentation) -> Data? {
        guard let tiff = image(for: presentation)?.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}
