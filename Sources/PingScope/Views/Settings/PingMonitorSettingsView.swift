import AppKit
import Combine
import SwiftUI

@MainActor
struct PingMonitorSettingsView: View {
    @ObservedObject var hostListViewModel: HostListViewModel
    @ObservedObject var displayViewModel: DisplayViewModel

    private let notificationStore: NotificationPreferencesStore
    private let onSetCompactModeEnabled: (Bool) -> Void
    private let onSetStayOnTopEnabled: (Bool) -> Void
    private let onResetAll: () -> Void
    private let onClose: () -> Void

    @AppStorage("menuBar.mode.compact") private var compactModeEnabled: Bool = false
    @AppStorage("menuBar.mode.stayOnTop") private var stayOnTopEnabled: Bool = false

    @State private var startOnLaunchEnabled: Bool = false
    @State private var preferences: NotificationPreferences

    init(
        hostListViewModel: HostListViewModel,
        displayViewModel: DisplayViewModel,
        notificationStore: NotificationPreferencesStore = NotificationPreferencesStore(),
        onSetCompactModeEnabled: @escaping (Bool) -> Void,
        onSetStayOnTopEnabled: @escaping (Bool) -> Void,
        onResetAll: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.hostListViewModel = hostListViewModel
        self.displayViewModel = displayViewModel
        self.notificationStore = notificationStore
        self.onSetCompactModeEnabled = onSetCompactModeEnabled
        self.onSetStayOnTopEnabled = onSetStayOnTopEnabled
        self.onResetAll = onResetAll
        self.onClose = onClose

        _preferences = State(initialValue: notificationStore.loadPreferences())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            applicationSection
            displaySection
            notificationSection
            hostsSection
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 540, height: 620)
        .onAppear {
            reloadFromStores()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard NSApp.keyWindow?.title == "PingMonitor Settings" else {
                return
            }

            reloadFromStores()
        }
        .sheet(isPresented: $hostListViewModel.showingAddSheet) {
            AddHostSheet(
                viewModel: AddHostViewModel(
                    mode: .add,
                    onSave: { host in
                        hostListViewModel.addHost(host)
                    },
                    onCancel: {}
                )
            )
            .frame(minWidth: 360, minHeight: 320)
        }
        .sheet(item: $hostListViewModel.hostToEdit) { host in
            AddHostSheet(
                viewModel: AddHostViewModel(
                    mode: .edit(host),
                    onSave: { updatedHost in
                        hostListViewModel.updateHost(updatedHost)
                    },
                    onCancel: {}
                )
            )
            .frame(minWidth: 360, minHeight: 320)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteDialogIsPresented,
            presenting: hostListViewModel.hostToDelete,
            actions: { host in
                Button("Remove", role: .destructive) {
                    hostListViewModel.confirmDelete()
                }
                Button("Cancel", role: .cancel) {}
            },
            message: { _ in
                Text("This action cannot be undone.")
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PingMonitor Settings")
                .font(.system(size: 22, weight: .semibold))
            Text("Manage hosts for network monitoring")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var applicationSection: some View {
        SettingsGroup(title: "Application") {
            HStack(alignment: .center, spacing: 22) {
                SettingsToggleRow(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    tint: .blue,
                    title: "Compact Mode",
                    isOn: Binding(
                        get: { compactModeEnabled },
                        set: { newValue in
                            compactModeEnabled = newValue
                            onSetCompactModeEnabled(newValue)
                        }
                    )
                )

                SettingsToggleRow(
                    systemImage: "pin.fill",
                    tint: .orange,
                    title: "Stay on Top",
                    isOn: Binding(
                        get: { stayOnTopEnabled },
                        set: { newValue in
                            stayOnTopEnabled = newValue
                            onSetStayOnTopEnabled(newValue)
                        }
                    )
                )

                SettingsToggleRow(
                    systemImage: "power.circle.fill",
                    tint: .green,
                    title: "Start on Launch",
                    isOn: Binding(
                        get: { startOnLaunchEnabled },
                        set: { newValue in
                            let success = StartOnLaunchService.setEnabled(newValue)
                            startOnLaunchEnabled = success ? newValue : StartOnLaunchService.isEnabled()
                        }
                    )
                )
            }
        }
    }

    private var displaySection: some View {
        SettingsGroup(title: "Display") {
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                SettingsToggleRow(
                    systemImage: "rectangle.stack.fill",
                    tint: .purple,
                    title: "Monitored Hosts",
                    isOn: Binding(
                        get: { displayViewModel.showsMonitoredHosts },
                        set: { displayViewModel.setShowsMonitoredHosts($0) }
                    )
                )

                SettingsToggleRow(
                    systemImage: "chart.xyaxis.line",
                    tint: .blue,
                    title: "Show Graph",
                    isOn: Binding(
                        get: { displayViewModel.modeState(for: .full).graphVisible },
                        set: { displayViewModel.setGraphVisible($0, for: .full) }
                    )
                )

                SettingsToggleRow(
                    systemImage: "clock.arrow.circlepath",
                    tint: .cyan,
                    title: "Show History",
                    isOn: Binding(
                        get: { displayViewModel.modeState(for: .full).historyVisible },
                        set: { displayViewModel.setHistoryVisible($0, for: .full) }
                    )
                )

                SettingsToggleRow(
                    systemImage: "doc.plaintext",
                    tint: .orange,
                    title: "History Summary",
                    isOn: Binding(
                        get: { displayViewModel.showsHistorySummary },
                        set: { displayViewModel.setShowsHistorySummary($0) }
                    )
                )
            }
        }
    }

    private var notificationSection: some View {
        SettingsGroup(title: "Notifications") {
            SettingsToggleRow(
                systemImage: "bell.fill",
                tint: .purple,
                title: "Enable Notifications",
                isOn: binding(for: \NotificationPreferences.globalEnabled)
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                SettingsToggleRow(
                    systemImage: "wifi.slash",
                    tint: .red,
                    title: "Alert on no internet",
                    isOn: enabledAlertTypeBinding(.internetLoss)
                )
                .disabled(!preferences.globalEnabled)

                SettingsToggleRow(
                    systemImage: "globe",
                    tint: .orange,
                    title: "Alert on network change",
                    isOn: enabledAlertTypeBinding(.networkChange)
                )
                .disabled(!preferences.globalEnabled)
            }

            SettingsToggleRow(
                systemImage: "rectangle.stack.badge.bell",
                tint: .blue,
                title: "Enable for all hosts",
                isOn: Binding(
                    get: { allHostsNotificationsEnabled },
                    set: { setAllHostsNotificationsEnabled($0) }
                )
            )
            .disabled(!preferences.globalEnabled)

            Text("Individual host notification settings can be configured when editing each host")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
    }

    private var hostsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Monitored Hosts")
                    .font(.headline)

                Spacer()

                Button {
                    hostListViewModel.triggerAdd()
                } label: {
                    Label("Add Host", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 10) {
                ForEach(hostListViewModel.hosts) { host in
                    HostSettingsRow(
                        host: host,
                        isActive: hostListViewModel.isActive(host),
                        status: status(for: host),
                        onEdit: { hostListViewModel.triggerEdit(host) },
                        onRemove: { hostListViewModel.triggerDelete(host) }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                onResetAll()
                reloadFromStores()
            }

            Spacer()

            Button("Cancel") {
                onClose()
            }

            Button("Done") {
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var deleteDialogTitle: String {
        if let host = hostListViewModel.hostToDelete {
            return "Remove \(host.name)?"
        }
        return "Remove host?"
    }

    private var deleteDialogIsPresented: Binding<Bool> {
        Binding(
            get: { hostListViewModel.hostToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    hostListViewModel.hostToDelete = nil
                }
            }
        )
    }

    private func binding<Value>(for keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { newValue in
                preferences[keyPath: keyPath] = newValue
                notificationStore.savePreferences(preferences)
            }
        )
    }

    private func enabledAlertTypeBinding(_ alertType: AlertType) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledAlertTypes.contains(alertType) },
            set: { enabled in
                if enabled {
                    preferences.enabledAlertTypes.insert(alertType)
                } else {
                    preferences.enabledAlertTypes.remove(alertType)
                }

                notificationStore.savePreferences(preferences)
            }
        )
    }

    private func reloadFromStores() {
        startOnLaunchEnabled = StartOnLaunchService.isEnabled()
        preferences = notificationStore.loadPreferences()
    }

    private var allHostsNotificationsEnabled: Bool {
        hostListViewModel.hosts.allSatisfy { $0.notificationsEnabled }
    }

    private func setAllHostsNotificationsEnabled(_ enabled: Bool) {
        for host in hostListViewModel.hosts {
            hostListViewModel.updateHost(host.withNotificationsEnabled(enabled))
        }
    }

    private func status(for host: Host) -> HostStatus {
        guard let latencyEntry = hostListViewModel.latencies[host.id] else {
            return .unknown
        }

        guard let latencyMS = latencyEntry else {
            return .failure
        }

        if latencyMS <= 80 {
            return .good
        }
        if latencyMS <= 150 {
            return .warning
        }
        return .poor
    }
}

enum HostStatus {
    case good
    case warning
    case poor
    case failure
    case unknown
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.leading, 2)
        }
    }
}

private struct SettingsToggleRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
        }
    }
}

private struct HostSettingsRow: View {
    let host: Host
    let isActive: Bool
    let status: HostStatus
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(host.name)
                .font(.system(size: 15, weight: .semibold))

            if isActive {
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.25))
                    .foregroundStyle(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(host.address)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if host.notificationsEnabled {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .accessibilityLabel("Notifications enabled")
            }

            Spacer()

            Button("Edit") {
                onEdit()
            }
            .buttonStyle(.bordered)

            Button("Remove") {
                onRemove()
            }
            .buttonStyle(.bordered)
            .disabled(host.isDefault)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .good:
            return .green
        case .warning:
            return .yellow
        case .poor:
            return .red
        case .failure:
            return .red
        case .unknown:
            return .gray
        }
    }
}
