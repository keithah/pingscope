import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var history: some View {
        SettingsPane {
            SettingsSection("Export") {
                SettingsRow(systemImage: "server.rack", tint: .blue, title: "Host") {
                    // An optional selection avoids minting a fresh UUID() on
                    // every body evaluation when no host exists, which would
                    // never match a tag and churn the Picker's selection.
                    Picker("Host", selection: Binding<UUID?>(
                        get: { model.historyExportHost?.id ?? model.primaryHost?.id ?? model.snapshot.hosts.first?.id },
                        set: { model.historyExportHostID = $0 }
                    )) {
                        ForEach(model.snapshot.hosts) { host in
                            Text(host.displayName).tag(host.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsRow(systemImage: "clock", tint: .purple, title: "Range") {
                    Picker("Range", selection: $model.historyExportRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                SettingsRow(systemImage: "square.and.arrow.down", tint: .green, title: "Export") {
                    HStack(spacing: 10) {
                        ForEach(HistoryExportFormat.allCases) { format in
                            Button(format.displayName) {
                                model.exportHistory(format: format)
                            }
                            .disabled(model.isExportingHistory || model.snapshot.hosts.isEmpty)
                        }
                    }
                }

                if let message = model.historyExportMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }

            SettingsSection("Storage") {
                SettingsRow(systemImage: "externaldrive", tint: .gray, title: "Retention") {
                    Text("7 days")
                        .foregroundStyle(.secondary)
                }
                Text("History is stored locally and pruned automatically. Export uses the selected host and range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        }
    }

}
