import AppKit
import Foundation
import PingScopeCore

extension PingScopeModel {
    @MainActor private static let diagnosticsDateFormatter = ISO8601DateFormatter()

    func diagnosticsSummary() -> String {
        let host = primaryHost
        let latest = primaryHealth.latestResult
        let failures = recentDiagnosticFailures
            .map { result in
                let time = Self.diagnosticsDateFormatter.string(from: result.timestamp)
                let reason = result.failureReason?.rawValue ?? "unknown"
                let note = result.metadata.note.map { " note=\($0)" } ?? ""
                return "- \(time) \(result.method.rawValue.uppercased()) \(result.address)\(result.port.map { ":\($0)" } ?? "") \(reason)\(note)"
            }
            .joined(separator: "\n")

        return """
        PingScope Diagnostics
        Build flavor: \(BuildFlavor.current == .appStore ? "App Store" : "Developer ID")
        Primary host: \(host?.displayName ?? "None")
        Address: \(host?.address ?? "None")
        Method: \(host?.method.rawValue.uppercased() ?? "None")
        Network status: \(currentNetworkStatus.displayName)
        Local network probes: \(allowsLocalNetworkProbes ? "enabled" : "disabled")
        Latest result: \(latest?.latency.map { "\(Int($0.milliseconds.rounded()))ms" } ?? latest?.failureReason?.rawValue ?? "none")
        Log path: \(diagnosticsLogURL.path)

        Recent failures:
        \(failures.isEmpty ? "None in the selected range." : failures)
        """
    }

    func revealDiagnosticsLog() {
        if !FileManager.default.fileExists(atPath: diagnosticsLogURL.path) {
            DebugLog.write("diagnostics log created from settings")
            Task {
                await DebugLog.flush()
                NSWorkspace.shared.activateFileViewerSelecting([diagnosticsLogURL])
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([diagnosticsLogURL])
        }
        setDiagnosticsMessage("Opened log in Finder")
    }

    func copyDiagnosticsSummary() {
        let summary = diagnosticsSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        setDiagnosticsMessage("Copied diagnostics summary")
    }
}
