import AppKit
import SwiftUI

@main
struct PingScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsTabView()
        }
    }
}

struct SettingsTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HostSettingsView()
                .tabItem {
                    Label("Hosts", systemImage: "server.rack")
                }
                .tag(0)

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(1)

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }
                .tag(2)
        }
        .frame(width: 480, height: 420)
        .padding()
    }
}

struct DisplaySettingsView: View {
    @AppStorage("menuBar.mode.compact") private var isCompactModeEnabled = false
    @AppStorage("menuBar.mode.stayOnTop") private var isStayOnTopEnabled = false

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Compact Mode", isOn: compactModeBinding)
                Toggle("Stay on Top", isOn: stayOnTopBinding)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }

    private var compactModeBinding: Binding<Bool> {
        Binding(
            get: { isCompactModeEnabled },
            set: { isEnabled in
                isCompactModeEnabled = isEnabled
                (NSApp.delegate as? AppDelegate)?.setCompactModeEnabled(isEnabled)
            }
        )
    }

    private var stayOnTopBinding: Binding<Bool> {
        Binding(
            get: { isStayOnTopEnabled },
            set: { isEnabled in
                isStayOnTopEnabled = isEnabled
                (NSApp.delegate as? AppDelegate)?.setStayOnTopEnabled(isEnabled)
            }
        )
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        SettingsTabView()
    }
}

#Preview {
    SettingsTabView()
}
