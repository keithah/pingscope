import PingScopeCore
import PingScopeHistoryKit
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
                        get: { model.historyExportHost?.id ?? model.configuredPrimaryHost?.id ?? model.configuredHosts.first?.id },
                        set: { model.historyExportHostID = $0 }
                    )) {
                        ForEach(model.configuredHosts) { host in
                            Text(host.displayName).tag(host.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsRow(systemImage: "clock", tint: .purple, title: "Range") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Range", selection: $model.historyExportRange) {
                            ForEach(HistoryExportRangePreset.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)

                        if model.historyExportRange == .custom {
                            HStack(spacing: 8) {
                                TextField("Amount", text: $model.historyExportCustomValue)
                                    .labelsHidden()
                                    .frame(width: 70)
                                Picker("Unit", selection: $model.historyExportCustomUnit) {
                                    ForEach(HistoryExportRangeUnit.allCases) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 100)
                            }
                        }
                    }
                }

                if model.historyExportRange == .max {
                    Text("Max exports the full retained history for the selected host, up to 30 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                } else if model.historyExportRange == .custom {
                    Text("Custom ranges are capped at the retained 30-day history window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }

                SettingsRow(systemImage: "square.and.arrow.down", tint: .green, title: "Export") {
                    HStack(spacing: 10) {
                        ForEach(HistoryExportFormat.allCases) { format in
                            Button(format.displayName) {
                                model.exportHistory(format: format)
                            }
                            .disabled(model.isExportingHistory || model.configuredHosts.isEmpty)
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
                    Text("30 days")
                        .foregroundStyle(.secondary)
                }
                Text("History is stored locally and pruned automatically. Use Max to export the full retained window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }

        }
    }

}
