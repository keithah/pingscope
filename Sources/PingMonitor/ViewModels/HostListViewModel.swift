import Combine
import Foundation

@MainActor
final class HostListViewModel: ObservableObject {
    @Published var hosts: [Host] = []
    @Published var activeHostID: UUID?
    @Published var latencies: [UUID: Double?] = [:]
    @Published var showingAddSheet: Bool = false
    @Published var hostToEdit: Host?
    @Published var hostToDelete: Host?

    private let onSelectHost: (Host) -> Void
    private let onAddHost: (Host) -> Void
    private let onUpdateHost: (Host) -> Void
    private let onDeleteHost: (Host) -> Void

    init(
        hosts: [Host] = [],
        activeHostID: UUID? = nil,
        onSelectHost: @escaping (Host) -> Void,
        onAddHost: @escaping (Host) -> Void = { _ in },
        onUpdateHost: @escaping (Host) -> Void = { _ in },
        onDeleteHost: @escaping (Host) -> Void = { _ in }
    ) {
        self.hosts = hosts
        self.activeHostID = activeHostID
        self.onSelectHost = onSelectHost
        self.onAddHost = onAddHost
        self.onUpdateHost = onUpdateHost
        self.onDeleteHost = onDeleteHost
    }

    func selectHost(_ host: Host) {
        activeHostID = host.id
        onSelectHost(host)
    }

    func updateLatency(for hostID: UUID, latencyMS: Double?) {
        latencies[hostID] = latencyMS
    }

    func triggerAdd() {
        showingAddSheet = true
    }

    func triggerEdit(_ host: Host) {
        hostToEdit = host
    }

    func triggerDelete(_ host: Host) {
        hostToDelete = host
    }

    func confirmDelete() {
        guard let host = hostToDelete, !host.isDefault else {
            hostToDelete = nil
            return
        }

        onDeleteHost(host)
        hostToDelete = nil
    }

    func addHost(_ host: Host) {
        onAddHost(host)
    }

    func updateHost(_ host: Host) {
        onUpdateHost(host)
    }

    func isActive(_ host: Host) -> Bool {
        host.id == activeHostID
    }

    func latencyText(for host: Host) -> String {
        guard let latencyEntry = latencies[host.id] else {
            return ""
        }

        guard let latencyMS = latencyEntry else {
            return "Failed"
        }

        return "\(Int(latencyMS.rounded()))ms"
    }
}
