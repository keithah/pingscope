import PingScopeCore
import SwiftUI

#if os(iOS)
struct PingScopeIOSAllHostsRingGrid: View {
    let rows: [PingScopeIOSHostRowSnapshot]
    let onSelectHost: (UUID) -> Void
    @State private var contentMemo = PingScopeIOSAllHostsRingGridContentMemo()

    var body: some View {
        let cells = contentMemo.resolve(rows) {
            PingScopeIOSAllHostsRingGridPresentation.cells(from: $0)
        }
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], spacing: 12) {
                ForEach(cells) { cell in
                    Button {
                        onSelectHost(cell.hostID)
                    } label: {
                        ringCell(cell)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Focus \(cell.displayName)")
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private func ringCell(_ cell: PingScopeIOSAllHostsRingCell) -> some View {
        let color = Color(iosStatusColor: cell.status.iosStatusColor)
        return VStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: cell.ringProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(cell.latencyText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 72, height: 72)
            Text(cell.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cell.displayName), \(cell.status.displayName), \(cell.latencyText)")
    }

}

#endif
