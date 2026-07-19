import Foundation
import PingScopeCore

public actor PingScopeIOSFailureLogSuppressor {
    private var lastEmissionByHost: [UUID: (reason: FailureReason, date: Date)] = [:]

    public init() {}

    /// Suppresses only consecutive identical host failures for sixty seconds.
    /// Every reason transition, including a return to an earlier reason, is immediate.
    public func shouldLog(hostID: UUID, reason: FailureReason, at date: Date = Date()) -> Bool {
        if let previous = lastEmissionByHost[hostID],
           previous.reason == reason,
           date.timeIntervalSince(previous.date) < 60 { return false }
        lastEmissionByHost[hostID] = (reason, date)
        return true
    }
}

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
    private static let networkNameExpression = try! NSRegularExpression(
        pattern: #"(?i)(ssid|network(?: name)?)\s*[=:]\s*[^\n,;]+"#
    )
    private static let locationExpression = try! NSRegularExpression(
        pattern: #"(?i)(latitude|longitude|lat|lon)\s*[=:]\s*-?\d+(?:\.\d+)?"#
    )
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
        var literals = Set<String>()
        if !privacy.includesNetworkNames {
            literals.formUnion(samples.compactMap(\.networkName))
        }
        if !privacy.includesLocation {
            for location in samples.compactMap(\.location) {
                literals.insert(String(location.latitude))
                literals.insert(String(location.longitude))
            }
        }
        var result = replacingLiterals(in: log, literals: literals)
        if !privacy.includesNetworkNames {
            result = replacingMatches(in: result, expression: networkNameExpression, with: "$1=<redacted>")
        }
        if !privacy.includesLocation {
            result = replacingMatches(in: result, expression: locationExpression, with: "$1=<redacted>")
        }
        return result
    }

    private static func replacingLiterals(in value: String, literals: Set<String>) -> String {
        let ordered = literals.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !ordered.isEmpty,
              let expression = try? NSRegularExpression(pattern: ordered.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "<redacted>")
    }

    private static func replacingMatches(in value: String, expression: NSRegularExpression, with template: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
