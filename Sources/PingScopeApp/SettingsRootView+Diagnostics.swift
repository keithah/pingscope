import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var diagnostics: some View {
        SettingsPane {
            SettingsSection("Current State") {
                SettingsRow(systemImage: "server.rack", tint: .blue, title: "Primary host") {
                    Text(model.primaryHost?.displayName ?? "None")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "wifi", tint: .blue, title: "Network status") {
                    NetworkStatusBadge(status: model.currentNetworkStatus)
                }
                SettingsRow(systemImage: "waveform.path.ecg", tint: Color(statusColor: model.primaryHealth.status.statusColor), title: "Latest result") {
                    Text(diagnosticsLatestResult)
                        .foregroundStyle(model.primaryHealth.latestResult?.failureReason == nil ? Color.secondary : Color.red)
                }
            }

            SettingsSection("Debug Log") {
                SettingsRow(systemImage: "doc.text", tint: .gray, title: "Path") {
                    Text(model.diagnosticsLogURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                SettingsRow(systemImage: "wrench.and.screwdriver", tint: .orange, title: "Actions") {
                    HStack(spacing: 10) {
                        Button("Reveal Log") {
                            model.revealDiagnosticsLog()
                        }
                        Button("Copy Summary") {
                            model.copyDiagnosticsSummary()
                        }
                        Button("Clear Log", role: .destructive) {
                            model.clearDiagnosticsLog()
                        }
                    }
                }
                if let message = model.diagnosticsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }

            SettingsSection("Recent Failures") {
                if model.recentDiagnosticFailures.isEmpty {
                    Text("No failures in the selected graph range.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.recentDiagnosticFailures) { result in
                            DiagnosticFailureRow(result: result)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsLatestResult: String {
        guard let result = model.primaryHealth.latestResult else { return "No samples yet" }
        if let latency = result.latency {
            return "\(Int(latency.milliseconds.rounded()))ms"
        }
        return result.failureReason?.userMessage ?? "Failed"
    }
}
