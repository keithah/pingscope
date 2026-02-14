import SwiftUI

struct HostListView: View {
    @ObservedObject var viewModel: HostListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            List {
                ForEach(viewModel.hosts) { host in
                    HostRowView(
                        host: host,
                        isActive: viewModel.isActive(host),
                        latencyText: viewModel.latencyText(for: host),
                        onTap: { viewModel.selectHost(host) },
                        onEdit: { viewModel.triggerEdit(host) },
                        onDelete: { viewModel.triggerDelete(host) }
                    )
                }
            }
            .listStyle(.plain)
        }
        .padding(12)
        .sheet(isPresented: $viewModel.showingAddSheet) {
            Text("Add Host Sheet")
                .frame(minWidth: 320, minHeight: 220)
        }
        .sheet(item: $viewModel.hostToEdit) { _ in
            Text("Edit Host Sheet")
                .frame(minWidth: 320, minHeight: 220)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteDialogIsPresented,
            presenting: viewModel.hostToDelete,
            actions: { _ in
                Button("Delete", role: .destructive) {
                    viewModel.confirmDelete()
                }
                Button("Cancel", role: .cancel) {}
            },
            message: { _ in
                Text("This action cannot be undone.")
            }
        )
    }

    private var header: some View {
        HStack {
            Text("Hosts")
                .font(.headline)

            Spacer()

            Button {
                viewModel.triggerAdd()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add host")
        }
    }

    private var deleteDialogTitle: String {
        if let host = viewModel.hostToDelete {
            return "Delete \(host.name)?"
        }

        return "Delete host?"
    }

    private var deleteDialogIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.hostToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.hostToDelete = nil
                }
            }
        )
    }
}

#Preview {
    let hosts = [Host.googleDNS, Host.cloudflareDNS]

    HostListView(
        viewModel: HostListViewModel(
            hosts: hosts,
            activeHostID: hosts.first?.id,
            onSelectHost: { _ in }
        )
    )
}
