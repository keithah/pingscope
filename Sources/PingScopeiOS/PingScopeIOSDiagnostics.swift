import Foundation
import PingScopeCore

public struct PingScopeIOSDiagnosticsMetadata: Equatable, Sendable {
    public var appName: String
    public var version: String
    public var build: String
    public var buildFlavor: String

    public init(appName: String, version: String, build: String, buildFlavor: String) {
        self.appName = appName
        self.version = version
        self.build = build
        self.buildFlavor = buildFlavor
    }
}

public struct PingScopeIOSDiagnosticsPrivacy: Equatable, Sendable {
    public var includesLocation: Bool
    public var includesNetworkNames: Bool

    public init(includesLocation: Bool, includesNetworkNames: Bool) {
        self.includesLocation = includesLocation
        self.includesNetworkNames = includesNetworkNames
    }

    public static let redacted = Self(includesLocation: false, includesNetworkNames: false)
}

public enum PingScopeIOSDiagnosticsBundle {
    public static func text(
        metadata: PingScopeIOSDiagnosticsMetadata,
        logText: String,
        hosts: [HostConfig],
        recentSamples: [PingResult],
        privacy: PingScopeIOSDiagnosticsPrivacy
    ) -> String {
        var lines = [
            "PingScope Diagnostics",
            "App: \(metadata.appName)",
            "Version: \(metadata.version) (\(metadata.build))",
            "Build flavor: \(metadata.buildFlavor)",
            "",
            "Configured hosts:"
        ]

        if hosts.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: hosts.map { "- \($0.displayName) · \($0.method.rawValue.uppercased())" })
        }

        lines.append(contentsOf: ["", "Recent samples:"])
        if recentSamples.isEmpty {
            lines.append("- None")
        } else {
            for sample in recentSamples {
                lines.append("- Host: \(sample.hostID.uuidString); timestamp: \(sample.timestamp.timeIntervalSince1970)")
                lines.append("  Interface: \(sample.networkInterface ?? "Unknown")")
                lines.append("  Network name: \(networkName(for: sample, privacy: privacy))")
                lines.append("  Location: \(location(for: sample, privacy: privacy))")
            }
        }

        lines.append(contentsOf: ["", "Recent log:", redactedLog(logText, samples: recentSamples, privacy: privacy)])
        return lines.joined(separator: "\n")
    }

    private static func networkName(
        for sample: PingResult,
        privacy: PingScopeIOSDiagnosticsPrivacy
    ) -> String {
        guard privacy.includesNetworkNames else { return "<redacted>" }
        return sample.networkName ?? "Unknown"
    }

    private static func location(
        for sample: PingResult,
        privacy: PingScopeIOSDiagnosticsPrivacy
    ) -> String {
        guard privacy.includesLocation else { return "<redacted>" }
        guard let location = sample.location else { return "Unknown" }
        return "\(location.latitude), \(location.longitude)"
    }

    private static func redactedLog(
        _ log: String,
        samples: [PingResult],
        privacy: PingScopeIOSDiagnosticsPrivacy
    ) -> String {
        // Defense in depth: correctness also relies on callers never writing raw
        // location or SSID values to DebugLog; sensitive values use DebugLog.redacted().
        var result = log
        if !privacy.includesNetworkNames {
            for name in Set(samples.compactMap(\.networkName)).sorted(by: { $0.count > $1.count }) {
                result = result.replacingOccurrences(of: name, with: "<redacted>")
            }
            result = replacingMatches(in: result, pattern: #"(?i)(ssid|network(?: name)?)\s*[=:]\s*[^\n,;]+"#, with: "$1=<redacted>")
        }
        if !privacy.includesLocation {
            for location in samples.compactMap(\.location) {
                result = result.replacingOccurrences(of: String(location.latitude), with: "<redacted>")
                result = result.replacingOccurrences(of: String(location.longitude), with: "<redacted>")
            }
            result = replacingMatches(in: result, pattern: #"(?i)(latitude|longitude|lat|lon)\s*[=:]\s*-?\d+(?:\.\d+)?"#, with: "$1=<redacted>")
        }
        return result
    }

    private static func replacingMatches(in value: String, pattern: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
