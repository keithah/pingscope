import AppKit
import SwiftUI

@main
struct PingScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            DisplaySettingsView()
        }
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
        DisplaySettingsView()
    }
}

#Preview {
    DisplaySettingsView()
        .frame(width: 360)
}
