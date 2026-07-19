import PingScopeCore
import SwiftUI

#if os(iOS)
struct PingScopeIOSAllHostsConcentricRingHero: View {
    private static let identityColors: [Color] = [.blue, .cyan, .orange, .pink, .mint, .indigo]

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
                        if presentation.overflowCount > 0 {
                            HStack {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                                Text(presentation.overflowLabel)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
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
        ZStack {
            ForEach(rings) { ring in
                let diameter = CGFloat(76 + ring.ringIndex * 24)
                Circle()
                    .stroke(identityColor(ring.colorIndex).opacity(0.16), lineWidth: 8)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .trim(from: 0, to: ring.ringProgress)
                    .stroke(identityColor(ring.colorIndex), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
            }
            VStack(spacing: 2) {
                Text("All Hosts")
                    .font(.subheadline.weight(.semibold))
                Text("\(rings.count) shown")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 164)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All hosts concentric latency rings, innermost to outermost in saved order")
    }

    private func legendRow(_ row: PingScopeIOSAllHostsRingCell) -> some View {
        Button {
            onSelectHost(row.hostID)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(identityColor(row.colorIndex))
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
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.displayName), \(row.status.displayName), \(row.latencyText)")
        .accessibilityHint("Focus \(row.displayName)")
    }

    private func identityColor(_ index: Int) -> Color {
        Self.identityColors[index % Self.identityColors.count]
    }
}

#endif
