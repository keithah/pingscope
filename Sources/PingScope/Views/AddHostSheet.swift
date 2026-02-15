import SwiftUI

struct AddHostSheet: View {
    @StateObject var viewModel: AddHostViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AddHostViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                hostDetailsSection
                testConnectionSection
                advancedSection
                notificationsSection
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }

    private var hostDetailsSection: some View {
        Section("Host Details") {
            TextField("Hostname or IP", text: $viewModel.hostname)
                .applyHostAddressInputModifiers()
            TextField("Display Name", text: $viewModel.displayName)

            Picker("Ping Method", selection: $viewModel.pingMethod) {
                ForEach(PingMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }

            TextField("Port", text: $viewModel.port, prompt: Text("\(viewModel.pingMethod.defaultPort)"))
                .applyNumberPadKeyboard()
        }
    }

    private var testConnectionSection: some View {
        Section("Test Connection") {
            Button {
                Task {
                    await viewModel.testPing()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Test Ping")
                    if viewModel.isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(viewModel.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTesting)

            if let testResult = viewModel.testResult {
                switch testResult {
                case let .success(latencyMS):
                    Label("Connected: \(Int(latencyMS.rounded()))ms", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case let .failed(error):
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                case .none:
                    EmptyView()
                }
            }

            if viewModel.showTestWarning {
                Text("Save is still available even if this test fails.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            DisclosureGroup("Optional Overrides") {
                Toggle("Custom Interval", isOn: $viewModel.useCustomInterval)
                if viewModel.useCustomInterval {
                    TextField("Interval (seconds)", text: $viewModel.intervalSeconds)
                        .applyDecimalPadKeyboard()
                }

                Toggle("Custom Timeout", isOn: $viewModel.useCustomTimeout)
                if viewModel.useCustomTimeout {
                    TextField("Timeout (seconds)", text: $viewModel.timeoutSeconds)
                        .applyDecimalPadKeyboard()
                }

                Toggle("Custom Thresholds", isOn: $viewModel.useCustomThresholds)
                if viewModel.useCustomThresholds {
                    TextField("Green Threshold (ms)", text: $viewModel.greenThresholdMS)
                        .applyDecimalPadKeyboard()
                    TextField("Yellow Threshold (ms)", text: $viewModel.yellowThresholdMS)
                        .applyDecimalPadKeyboard()
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
        }
    }

    private var title: String {
        switch viewModel.mode {
        case .add:
            return "Add Host"
        case .edit:
            return "Edit Host"
        }
    }
}

private extension View {
    @ViewBuilder
    func applyHostAddressInputModifiers() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self
#endif
    }

    @ViewBuilder
    func applyNumberPadKeyboard() -> some View {
#if os(iOS)
        keyboardType(.numberPad)
#else
        self
#endif
    }

    @ViewBuilder
    func applyDecimalPadKeyboard() -> some View {
#if os(iOS)
        keyboardType(.decimalPad)
#else
        self
#endif
    }
}
