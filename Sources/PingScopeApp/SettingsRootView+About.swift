import AppKit
import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var about: some View {
        let attentionItems = aboutAttentionItems

        return SettingsPane {
            SettingsSection("PingScope") {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PingScope")
                            .font(.title2.weight(.semibold))
                        Text("Native latency monitoring for macOS.")
                            .foregroundStyle(.secondary)
                        Text("Version \(model.appVersionText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                SettingsRow(systemImage: "shippingbox", tint: .blue, title: "Build") {
                    Text(BuildFlavor.current == .appStore ? "App Store" : "Developer ID")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "number", tint: .gray, title: "Bundle ID") {
                    Text(model.bundleIdentifierText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "doc.text", tint: .purple, title: "License") {
                    Text("AGPLv3")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Links") {
                SettingsRow(systemImage: "globe", tint: .blue, title: "Website") {
                    Button("Open Product Page") {
                        NSWorkspace.shared.open(URL(string: "https://keithah.com/products/pingscope")!)
                    }
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
                    }
                #endif
                SettingsRow(systemImage: "lock.shield", tint: .green, title: "Privacy") {
                    Text("Settings, history, exports, and widget snapshots stay local.")
                        .foregroundStyle(.secondary)
                }
                if !attentionItems.isEmpty {
                    Divider()
                    Text("Needs attention")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(attentionItems) { item in
                            SetupChecklistRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private var aboutAttentionItems: [SetupChecklistItem] {
        let requiredSetupTitles: Set<String> = [
            "Primary host",
            "Notifications",
            "Local network"
        ]
        return model.setupChecklistItems.filter { item in
            requiredSetupTitles.contains(item.title) && !item.isComplete
        }
    }

}
