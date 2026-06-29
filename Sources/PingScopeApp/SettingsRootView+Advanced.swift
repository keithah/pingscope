import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var advanced: some View {
        SettingsPane {
            SettingsSection("App") {
                SettingsRow(systemImage: "shippingbox", tint: .blue, title: "Build flavor") {
                    Text(BuildFlavor.current == .appStore ? "App Store" : "Developer ID")
                        .foregroundStyle(.secondary)
                }
                #if !APPSTORE
                    if BuildFlavor.current != .appStore {
                        SettingsRow(systemImage: "arrow.triangle.2.circlepath", tint: .blue, title: "Software updates") {
                            HStack(spacing: 10) {
                                Text(softwareUpdateController.statusMessage)
                                    .foregroundStyle(.secondary)
                                Button("Check Now") {
                                    softwareUpdateController.checkForUpdates()
                                }
                                .disabled(!softwareUpdateController.canCheckForUpdates)
                            }
                        }
                        SettingsRow(systemImage: "link", tint: .teal, title: "Update feed") {
                            Text(softwareUpdateController.feedURL ?? "Not configured")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        SettingsRow(systemImage: "key.fill", tint: .orange, title: "Sparkle key") {
                            Text(softwareUpdateController.publicKeyConfigured ? "Configured" : "Missing")
                                .foregroundStyle(softwareUpdateController.publicKeyConfigured ? Color.secondary : Color.red)
                        }
                        SettingsRow(systemImage: "clock.arrow.circlepath", tint: .purple, title: "Last check") {
                            if let date = softwareUpdateController.lastCheckRequestedAt {
                                Text(date, style: .time)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not requested this session")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                #endif
                SettingsRow(systemImage: "waveform.path.ecg", tint: .green, title: "ICMP") {
                    Text(model.methodsForCurrentBuild.contains(.icmp) ? "Available" : "Hidden")
                        .foregroundStyle(.secondary)
                }
                SettingsToggleRow(systemImage: "power.circle.fill", tint: .green, title: "Start on login", isOn: $model.startsAtLogin)
                SettingsToggleRow(systemImage: "rectangle.inset.filled.and.person.filled", tint: .purple, title: "Share data with widgets", isOn: $model.widgetsEnabled)
            }

            SettingsSection("Network") {
                SettingsRow(systemImage: "wifi", tint: .blue, title: "Current status") {
                    NetworkStatusBadge(status: model.currentNetworkStatus)
                }
                SettingsToggleRow(systemImage: "network", tint: .purple, title: "Monitor local network hosts", isOn: $model.allowsLocalNetworkProbes)
            }
        }
    }

}
