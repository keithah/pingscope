import PingScopeCore
import SwiftUI

#if os(iOS)
import UIKit

struct PingScopeIOSHostEditor: View {
    @State private var draft: PingScopeIOSHostDraft

    let canDelete: Bool
    let onSave: (HostConfig) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        host: HostConfig,
        canDelete: Bool,
        onSave: @escaping (HostConfig) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: PingScopeIOSHostDraft(host: host))
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $draft.displayName)
                    TextField("Address", text: $draft.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }

                Section("Appearance") {
                    ColorPicker("Host Color", selection: displayColorSelection, supportsOpacity: false)

                    HStack {
                        Circle()
                            .fill(resolvedDisplayColor)
                            .frame(width: 16, height: 16)
                        Text(draft.usesAutomaticDisplayColor ? "Automatic Color" : "Custom Color")
                            .foregroundStyle(.secondary)
                    }

                    Button("Use Automatic Color") {
                        draft.displayColor = nil
                    }
                    .disabled(draft.usesAutomaticDisplayColor)
                }

                Section("Probe") {
                    Picker("Method", selection: methodBinding) {
                        ForEach(PingMethod.appStoreAvailableCases, id: \.self) { method in
                            Text(method.rawValue.uppercased()).tag(method)
                        }
                    }

                    TextField("Port", text: portText)
                        .keyboardType(.numberPad)
                        .disabled(draft.method == .icmp)
                }

                Section("Timing") {
                    Stepper(value: $draft.intervalMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Interval", value: "\(Int(draft.intervalMilliseconds))ms")
                    }
                    Stepper(value: $draft.timeoutMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Timeout", value: "\(Int(draft.timeoutMilliseconds))ms")
                    }
                }

                Section("Health") {
                    Stepper(value: $draft.degradedMilliseconds, in: 1...2_000, step: 25) {
                        LabeledContent("Degraded", value: "\(Int(draft.degradedMilliseconds))ms")
                    }
                    Stepper(value: $draft.downAfterFailures, in: 1...10) {
                        LabeledContent("Down after", value: "\(draft.downAfterFailures) failures")
                    }
                }

                if canDelete {
                    Section {
                        Button("Delete Host", role: .destructive) {
                            onDelete()
                        }
                    }
                }
            }
            .navigationTitle(draft.displayName.isEmpty ? "New Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.finalizedHost)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var methodBinding: Binding<PingMethod> {
        Binding(
            get: { draft.method },
            set: { method in
                draft.apply(method: method)
            }
        )
    }

    private var portText: Binding<String> {
        Binding(
            get: { draft.portText },
            set: { draft.portText = $0.filter(\.isNumber) }
        )
    }

    private var displayColorSelection: Binding<Color> {
        Binding(
            get: { resolvedDisplayColor },
            set: { color in
                if let displayColor = color.opaqueSRGBHostDisplayColor {
                    draft.displayColor = displayColor
                }
            }
        )
    }

    private var resolvedDisplayColor: Color {
        ResolvedHostDisplayColor(hostID: draft.id, displayColor: draft.displayColor).swiftUIColor
    }

    private var canSave: Bool {
        draft.canSave
    }
}

private extension Color {
    var opaqueSRGBHostDisplayColor: HostDisplayColor? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(self).cgColor.converted(
                to: colorSpace,
                intent: .defaultIntent,
                options: nil
              ),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        return HostDisplayColor(
            red: min(max(Double(components[0]), 0), 1),
            green: min(max(Double(components[1]), 0), 1),
            blue: min(max(Double(components[2]), 0), 1)
        )
    }
}
#endif
