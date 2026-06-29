import Foundation
import PingScopeCore

extension PingScopeModel {
    var setupChecklistItems: [SetupChecklistItem] {
        [
            SetupChecklistItem(
                title: "Primary host",
                detail: primaryHost?.displayName ?? "No primary host selected",
                isComplete: primaryHost != nil,
                actionTitle: nil,
                action: nil
            ),
            SetupChecklistItem(
                title: "Notifications",
                detail: notificationPermissionState.displayName,
                isComplete: [.authorized, .provisional].contains(notificationPermissionState),
                actionTitle: notificationPermissionState == .notDetermined ? "Request" : "Open Settings",
                action: { [weak self] in
                    if self?.notificationPermissionState == .notDetermined {
                        self?.requestNotificationPermission()
                    } else {
                        self?.openNotificationSettings()
                    }
                }
            ),
            SetupChecklistItem(
                title: "Local network",
                detail: allowsLocalNetworkProbes ? "Allowed for local hosts" : "Only public hosts",
                isComplete: allowsLocalNetworkProbes || !(primaryHost?.requiresLocalNetworkPermission ?? false),
                actionTitle: "Enable",
                action: { [weak self] in self?.allowsLocalNetworkProbes = true }
            ),
            SetupChecklistItem(
                title: "Overlay",
                detail: overlayVisible ? "Visible" : "Hidden",
                isComplete: overlayVisible,
                actionTitle: "Show",
                action: {
                    AppDelegate.shared?.showOverlay()
                }
            ),
            SetupChecklistItem(
                title: "Widgets",
                detail: widgetsStatusText,
                isComplete: widgetsEnabled,
                actionTitle: "Enable",
                action: { [weak self] in self?.widgetsEnabled = true }
            ),
            SetupChecklistItem(
                title: "Start at login",
                detail: startsAtLogin ? "Enabled" : "Disabled",
                isComplete: startsAtLogin,
                actionTitle: "Enable",
                action: { [weak self] in self?.startsAtLogin = true }
            )
        ]
    }
}
