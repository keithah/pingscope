import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var diagnostics: some View {
        SettingsDiagnosticsView(model: model, liveDisplay: model.liveDisplay)
    }
}

private struct SettingsDiagnosticsView: View {
    @ObservedObject var model: PingScopeModel
    @ObservedObject var liveDisplay: LiveDisplayModel

    var body: some View {
        SettingsPane {
            SettingsSection("Current State") {
                SettingsRow(systemImage: "server.rack", tint: .blue, title: "Primary host") {
                    Text(liveDisplay.snapshot.primaryHost?.displayName ?? "None")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "wifi", tint: .blue, title: "Network status") {
                    NetworkStatusBadge(status: model.currentNetworkStatus)
                }
                SettingsRow(systemImage: "waveform.path.ecg", tint: Color(statusColor: primaryHealth.status.statusColor), title: "Latest result") {
                    Text(diagnosticsLatestResult)
                        .foregroundStyle(primaryHealth.latestResult?.failureReason == nil ? Color.secondary : Color.red)
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
                if recentDiagnosticFailures.isEmpty {
                    Text("No failures in the selected graph range.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentDiagnosticFailures) { result in
                            DiagnosticFailureRow(result: result)
                        }
                    }
                }
            }
        }
    }

    private var primaryHealth: HostHealth {
        liveDisplay.snapshot.primaryHealth
            ?? HostHealth(hostID: liveDisplay.snapshot.primaryHost?.id ?? UUID())
    }

    private var recentDiagnosticFailures: [PingResult] {
        var failures: [PingResult] = []
        failures.reserveCapacity(8)
        for sample in liveDisplay.displayPresentation.visibleSamples.reversed() where sample.failureReason != nil {
            failures.append(sample)
            if failures.count == 8 {
                break
            }
        }
        return failures
    }

    private var diagnosticsLatestResult: String {
        guard let result = primaryHealth.latestResult else { return "No samples yet" }
        if let latency = result.latency {
            return "\(Int(latency.milliseconds.rounded()))ms"
        }
        return result.failureReason?.userMessage ?? "Failed"
    }
}
