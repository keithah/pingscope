import AppKit
import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var about: some View {
        SettingsPane {
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

            SettingsSection("First Run Checklist") {
                VStack(spacing: 8) {
                    ForEach(model.setupChecklistItems) { item in
                        SetupChecklistRow(item: item)
                    }
                }
            }

            SettingsSection("Links") {
                SettingsRow(systemImage: "globe", tint: .blue, title: "GitHub") {
                    Button("Open Repository") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/keithah/pingscope")!)
                    }
                }
                SettingsRow(systemImage: "lock.shield", tint: .green, title: "Privacy") {
                    Text("Settings, history, exports, and widget snapshots stay local.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

}
