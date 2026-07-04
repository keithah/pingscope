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
