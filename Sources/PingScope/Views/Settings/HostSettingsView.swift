import SwiftUI

struct HostSettingsView: View {
    @State private var hosts: [Host] = []
    @State private var selectedHostID: UUID? = nil
    @State private var showingAddSheet = false
    @State private var editingHost: Host? = nil

    @State private var store = HostStore()

    var body: some View {
        VStack(spacing: 10) {
            List {
                ForEach(hosts) { host in
                    hostRow(for: host)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    removeSelectedHost()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedHost == nil || (selectedHost?.isDefault ?? true))

                Spacer()

                Button("Edit") {
                    if let selectedHost {
                        editingHost = selectedHost
                    }
                }
                .disabled(selectedHost == nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
        }
        .frame(width: 400, height: 300)
        .task {
            await reloadHosts()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddHostSheet(
                viewModel: AddHostViewModel(
                    mode: .add,
                    onSave: { host in
                        Task {
                            await store.add(host)
                            await reloadHosts(selecting: host.id)
                        }
                    },
                    onCancel: {}
                )
            )
            .frame(minWidth: 360, minHeight: 320)
        }
        .sheet(item: $editingHost) { host in
            AddHostSheet(
                viewModel: AddHostViewModel(
                    mode: .edit(host),
                    onSave: { updatedHost in
                        Task {
                            await store.update(updatedHost)
                            await reloadHosts(selecting: updatedHost.id)
                        }
                    },
                    onCancel: {}
                )
            )
            .frame(minWidth: 360, minHeight: 320)
        }
    }

    private var selectedHost: Host? {
        guard let selectedHostID else {
            return nil
        }

        return hosts.first { $0.id == selectedHostID }
    }

    private func hostRow(for host: Host) -> some View {
        let isSelected = (host.id == selectedHostID)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(host.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                Image(systemName: host.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(host.notificationsEnabled ? "Notifications enabled" : "Notifications disabled")
            }

            Text("\(host.address):\(host.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHostID = host.id
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contextMenu {
            Button("Edit") {
                editingHost = host
            }

            if !host.isDefault {
                Button("Delete", role: .destructive) {
                    selectedHostID = host.id
                    removeSelectedHost()
                }
            }
        }
    }

    private func removeSelectedHost() {
        guard let selectedHost else {
            return
        }

        Task {
            await store.remove(selectedHost)
            await reloadHosts(selecting: nil)
        }
    }

    private func reloadHosts(selecting hostID: UUID? = nil) async {
        let loaded = await store.allHosts
        await MainActor.run {
            hosts = loaded
            selectedHostID = hostID
        }
    }
}
