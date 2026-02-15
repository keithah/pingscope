import Combine
import Foundation

@MainActor
final class StatusPopoverViewModel: ObservableObject {
    enum Section: Equatable {
        case status
        case quickActions
    }

    struct Snapshot: Equatable {
        var statusLabel: String
        var statusCategory: MenuBarStatus
        var latencyText: String
        var hostSummary: String

        static let placeholder = Snapshot(
            statusLabel: "No Data",
            statusCategory: .gray,
            latencyText: "N/A",
            hostSummary: "N/A"
        )
    }

    struct QuickAction: Identifiable, Equatable {
        enum Kind: String {
            case refresh
            case switchHost
            case settings
        }

        let kind: Kind
        let title: String

        var id: String {
            kind.rawValue
        }
    }

    @Published private(set) var snapshot: Snapshot
    @Published private(set) var networkChangeIndicator: Bool = false
    let sections: [Section] = [.status, .quickActions]

    let quickActions: [QuickAction] = [
        QuickAction(kind: .refresh, title: "Refresh"),
        QuickAction(kind: .switchHost, title: "Switch Host"),
        QuickAction(kind: .settings, title: "Settings")
    ]

    private let onRefresh: () -> Void
    private let onSwitchHost: () -> Void
    private let onOpenSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        menuBarViewModel: MenuBarViewModel,
        onRefresh: @escaping () -> Void = {},
        onSwitchHost: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        snapshot = Self.makeSnapshot(
            status: menuBarViewModel.status,
            latencyText: menuBarViewModel.compactLatencyText,
            hostSummary: menuBarViewModel.selectedHostSummary
        )
        self.onRefresh = onRefresh
        self.onSwitchHost = onSwitchHost
        self.onOpenSettings = onOpenSettings

        menuBarViewModel.$menuBarState
            .combineLatest(menuBarViewModel.$selectedHostSummary)
            .sink { [weak self] menuBarState, hostSummary in
                self?.snapshot = Self.makeSnapshot(
                    status: menuBarState.status,
                    latencyText: menuBarState.displayText,
                    hostSummary: hostSummary
                )
            }
            .store(in: &cancellables)
    }

    init(
        initialSnapshot: Snapshot,
        onRefresh: @escaping () -> Void = {},
        onSwitchHost: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        snapshot = initialSnapshot
        self.onRefresh = onRefresh
        self.onSwitchHost = onSwitchHost
        self.onOpenSettings = onOpenSettings
    }

    func perform(_ action: QuickAction.Kind) {
        switch action {
        case .refresh:
            onRefresh()
        case .switchHost:
            onSwitchHost()
        case .settings:
            onOpenSettings()
        }
    }

    func setNetworkChangeIndicator(_ isVisible: Bool) {
        networkChangeIndicator = isVisible
    }

    static func makeSnapshot(status: MenuBarStatus, latencyText: String?, hostSummary: String?) -> Snapshot {
        Snapshot(
            statusLabel: statusLabel(for: status),
            statusCategory: status,
            latencyText: sanitize(latencyText),
            hostSummary: sanitize(hostSummary)
        )
    }

    private static func statusLabel(for status: MenuBarStatus) -> String {
        switch status {
        case .green:
            return "Healthy"
        case .yellow:
            return "Degraded"
        case .red:
            return "Connection Lost"
        case .gray:
            return "No Data"
        }
    }

    private static func sanitize(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "N/A"
        }

        return value
    }
}
