import SwiftUI

struct HostRowView: View {
    let host: Host
    let isActive: Bool
    let latencyText: String
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            indicatorSymbol(systemName: "checkmark", showsSymbol: isActive)
            indicatorSymbol(systemName: "lock.fill", showsSymbol: host.isDefault)

            Text(host.name)
                .lineLimit(1)

            Spacer()

            Text(latencyText)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Edit") {
                onEdit()
            }

            if !host.isDefault {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    private func indicatorSymbol(systemName: String, showsSymbol: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .opacity(showsSymbol ? 1 : 0)
            .frame(width: 12)
            .accessibilityHidden(true)
    }
}
