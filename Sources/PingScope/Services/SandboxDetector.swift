import Foundation

enum SandboxDetector {
    /// Returns true if the app is running in the App Store sandbox.
    /// App Store sandbox places app container in /Library/Containers/.
    static var isRunningInSandbox: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }
}
