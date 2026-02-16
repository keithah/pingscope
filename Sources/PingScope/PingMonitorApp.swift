import AppKit
import SwiftUI

@main
struct PingScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsSceneView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    (NSApp.delegate as? AppDelegate)?.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

struct SettingsSceneView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let delegate = NSApp.delegate as? AppDelegate {
            PingMonitorSettingsView(
                hostListViewModel: delegate.hostListViewModel,
                displayViewModel: delegate.displayViewModel,
                notificationStore: delegate.notificationPreferencesStore,
                onSetCompactModeEnabled: { delegate.setCompactModeEnabled($0) },
                onSetStayOnTopEnabled: { delegate.setStayOnTopEnabled($0) },
                onResetAll: { delegate.resetToDefaults() },
                onOpenAbout: { delegate.openAbout() },
                onClose: { dismiss() }
            )
        } else {
            Text("PingMonitor Settings")
                .padding()
        }
    }
}

#Preview {
    SettingsSceneView()
}
