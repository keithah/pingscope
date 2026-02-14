import SwiftUI

@main
struct PingMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("PingMonitor")
            .font(.largeTitle)
            .padding()
    }
}
