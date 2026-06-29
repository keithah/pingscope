import PingScopeCore
import SwiftUI

struct DiagnosticFailureRow: View {
    let result: PingResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(result.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(result.failureReason?.userMessage ?? "Failed")
                .foregroundStyle(.red)
                .frame(width: 150, alignment: .leading)
            Text("\(result.method.rawValue.uppercased()) \(result.address)\(result.port.map { ":\($0)" } ?? "")")
                .foregroundStyle(.secondary)
            if let note = result.metadata.note {
                Text(note)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SetupChecklistRow: View {
    let item: SetupChecklistItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle = item.actionTitle, let action = item.action, !item.isComplete {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct NetworkStatusBadge: View {
    let status: NetworkConnectivityStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: status.defaultColorHex))
                .frame(width: 10, height: 10)
            Text(status.displayName)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SettingsRow<Content: View>: View {
    var systemImage: String?
    var tint: Color
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = nil
        self.tint = .secondary
        self.title = title
        self.content = content()
    }

    init(systemImage: String, tint: Color, title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            Text(title)
                .frame(width: systemImage == nil ? 130 : 150, alignment: .leading)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
    }
}

struct SettingsToggleRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
        }
    }
}

struct HostSettingsRow: View {
    let host: HostConfig
    let isSelected: Bool
    let isPrimary: Bool
    let statusColor: Color
    let onSelect: () -> Void
    let onMakePrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.green)
                    }
                    if !host.isEnabled {
                        Text("OFF")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(host.method.rawValue.uppercased()) \(host.address)\(host.port.map { ":\($0)" } ?? "") • \(host.effectiveNetworkTier.shortName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Edit") {
                onSelect()
            }
            .buttonStyle(.bordered)
            if !isPrimary {
                Button("Primary") {
                    onMakePrimary()
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct UnitNumberField: View {
    @Binding var value: Double
    let unit: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            TextField(unit, value: $value, format: .number)
                .frame(width: width)
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

struct NetworkStatusToggleRow: View {
    let status: NetworkConnectivityStatus
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 10) {
                Text(status.displayName)
                    .frame(width: 120, alignment: .leading)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: status.defaultColorHex))
                    .frame(width: 82, height: 18)
            }
        }
        .toggleStyle(.checkbox)
    }
}
