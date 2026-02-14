import AppKit
import SwiftUI

@main
struct PingMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
        }
    }
}
struct SettingsPlaceholderView: View {
    var body: some View {
        Text("PingMonitor")
            .font(.title2)
            .padding()
    }
}
