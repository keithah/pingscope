import AppKit
import PingScopeCore
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: PingScopeModel
    @EnvironmentObject var softwareUpdateController: SoftwareUpdateController
    @State private var selectedSettingsTab: String
    @State var showsAdvancedNotificationThresholds = false

    init(model: PingScopeModel) {
        self.model = model
        _selectedSettingsTab = State(initialValue: UserDefaults.standard.string(forKey: "selectedSettingsTab") ?? "hosts")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 158)
                    .padding(.horizontal, 10)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    selectedSettingsHeader

                    if selectedTab == .display {
                        selectedSettingsContent
                            .padding(.bottom, 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            selectedSettingsContent
                                .padding(.bottom, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsFooter
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Color.black.opacity(0.08))
        }
        .frame(minWidth: 680, minHeight: 500)
        .onChange(of: selectedSettingsTab) { _, tab in
            UserDefaults.standard.set(tab, forKey: "selectedSettingsTab")
        }
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedSettingsTab) ?? .hosts
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PingScope")
                    .font(.system(size: 22, weight: .bold))
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsSidebarButton(tab)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func settingsSidebarButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedSettingsTab = tab.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 19)
                Text(tab.title)
                    .font(.system(size: 13, weight: selectedSettingsTab == tab.id ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSettingsTab == tab.id ? Color.white : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedSettingsTab == tab.id ? Color.accentColor : Color.clear)
        )
    }

    private var selectedSettingsHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selectedTab.systemImage)
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.system(size: 24, weight: .bold))
                Text(selectedTab.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSettingsTab {
        case SettingsTab.display.id:
            display
        case SettingsTab.notifications.id:
            notifications
        case SettingsTab.history.id:
            history
        case SettingsTab.diagnostics.id:
            diagnostics
        case SettingsTab.advanced.id:
            advanced
        case SettingsTab.about.id:
            about
        default:
            hosts
        }
    }

    private var settingsFooter: some View {
        HStack {
            Button("Reset to Defaults", role: .destructive) {
                model.resetToDefaults()
            }
            Spacer()
            Button("Quit PingScope") {
                NSApp.terminate(nil)
            }
            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case hosts
    case display
    case notifications
    case history
    case diagnostics
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hosts: "Hosts"
        case .display: "Display"
        case .notifications: "Notifications"
        case .history: "History"
        case .diagnostics: "Diagnostics"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .hosts: "Manage monitored endpoints, methods, thresholds, and primary selection."
        case .display: "Tune the menu bar indicator, overlay behavior, and graph range."
        case .notifications: "Control alert types, network status colors, and notification permission."
        case .history: "Export retained samples and review local storage behavior."
        case .diagnostics: "Inspect current state, failures, and debug log actions."
        case .advanced: "Configure local network probing, widgets, login, and update status."
        case .about: "Version, licensing, setup checklist, and project links."
        }
    }

    var systemImage: String {
        switch self {
        case .hosts: "server.rack"
        case .display: "display"
        case .notifications: "bell.badge"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

