import PingScopeCore
import SwiftUI

#if os(iOS)
import UIKit

struct PingScopeIOSAllHostsConcentricRingHero: View {
    @ScaledMetric(relativeTo: .body) private var ringLineWidth: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var ringSpacing: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var innerDiameter: CGFloat = 76

    let rows: [PingScopeIOSHostRowSnapshot]
    let onSelectHost: (UUID) -> Void
    @State private var contentMemo = PingScopeIOSAllHostsConcentricRingContentMemo()

    var body: some View {
        let presentation = contentMemo.resolve(rows)
        Group {
            if presentation.rings.isEmpty {
                ContentUnavailableView(
                    "No Enabled Hosts",
                    systemImage: "circle.dashed",
                    description: Text("Enable a host to show its latency ring.")
                )
                .frame(minHeight: 180)
            } else {
                HStack(spacing: 12) {
                    concentricRings(presentation.rings)
                    VStack(spacing: 8) {
                        ForEach(presentation.legendRows) { row in
                            legendRow(row)
                        }
                        if presentation.overflowCount > 0,
                           let firstOverflowHostID = presentation.firstOverflowHostID {
                            Button {
                                onSelectHost(firstOverflowHostID)
                            } label: {
                                HStack {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                    Text(presentation.overflowLabel)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(presentation.overflowAccessibilityLabel)
                            .accessibilityHint("Focus the first hidden host")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private func concentricRings(_ rings: [PingScopeIOSAllHostsRingCell]) -> some View {
        let maximumRingIndex = rings.map(\.ringIndex).max() ?? 0
        let outerDiameter = innerDiameter + CGFloat(maximumRingIndex) * ringSpacing
        let containerExtent = outerDiameter + ringLineWidth
        return ZStack {
            ForEach(rings) { ring in
                let diameter = innerDiameter + CGFloat(ring.ringIndex) * ringSpacing
                Circle()
                    .stroke(ring.resolvedColor.swiftUIColor.opacity(0.16), lineWidth: ringLineWidth)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .trim(from: 0, to: ring.ringProgress)
                    .stroke(ring.resolvedColor.swiftUIColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
                if ring.status == .down {
                    Circle()
                        .stroke(
                            Color(iosStatusColor: ring.status.iosStatusColor),
                            style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                        )
                        .frame(width: diameter + ringLineWidth / 2, height: diameter + ringLineWidth / 2)
                }
            }
            VStack(spacing: 2) {
                Text("All Hosts")
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.75)
                Text("\(rings.count) shown")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: containerExtent, height: containerExtent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All hosts concentric latency rings, innermost to outermost in saved order")
    }

    private func legendRow(_ row: PingScopeIOSAllHostsRingCell) -> some View {
        Button {
            onSelectHost(row.hostID)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(row.resolvedColor.swiftUIColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(row.status.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(iosStatusColor: row.status.iosStatusColor))
                }
                Spacer(minLength: 8)
                Text(row.latencyText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(row.resolvedColor.swiftUIColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.displayName), \(row.status.displayName), \(row.latencyText)")
        .accessibilityHint("Focus \(row.displayName)")
    }

}

extension ResolvedHostDisplayColor {
    var swiftUIColor: Color {
        Color(uiColor: UIColor { traits in
            let appearance: HostDisplayColorAppearance = traits.userInterfaceStyle == .dark ? .dark : .light
            let components = components(for: appearance)
            return UIColor(
                red: CGFloat(components.red),
                green: CGFloat(components.green),
                blue: CGFloat(components.blue),
                alpha: 1
            )
        })
    }
}

#endif
