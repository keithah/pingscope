import Foundation
import PingScopeCore

public struct NetworkDiagnosisPresentation: Equatable, Sendable {
    public enum Tone: String, Equatable, Sendable {
        case gray
        case green
        case yellow
        case orange
        case red
    }

    public let label: String
    public let detail: String
    public let systemImage: String
    public let tone: Tone
    public let accessibilityLabel: String
    public let showsCompactRow: Bool

    public init(diagnosis: NetworkPerspectiveDiagnosis) {
        label = diagnosis.title
        if let evidenceNote = diagnosis.evidenceNote, !evidenceNote.isEmpty {
            detail = Self.appendingSentence(evidenceNote, to: diagnosis.detail)
        } else {
            detail = diagnosis.detail
        }

        switch diagnosis.scope {
        case .localNetwork:
            systemImage = "network.slash"
            tone = .red
            showsCompactRow = true
        case .upstream:
            systemImage = "wifi.exclamationmark"
            tone = .orange
            showsCompactRow = true
        case .remoteService:
            systemImage = "exclamationmark.triangle.fill"
            tone = .yellow
            showsCompactRow = true
        case .partialDegradation:
            systemImage = "speedometer"
            tone = .yellow
            showsCompactRow = true
        case .noData:
            systemImage = "circle"
            tone = .gray
            showsCompactRow = false
        case .allReachable:
            systemImage = "checkmark.circle.fill"
            tone = .green
            showsCompactRow = false
        }

        var accessibilityParts = [diagnosis.title, diagnosis.detail]
        if let evidenceNote = diagnosis.evidenceNote, !evidenceNote.isEmpty {
            accessibilityParts.append(evidenceNote)
        }
        if diagnosis.confidence == .tentative {
            accessibilityParts.append(diagnosis.confidence.displayName)
        }
        accessibilityLabel = accessibilityParts
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private static func appendingSentence(_ sentence: String, to detail: String) -> String {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = trimmedDetail.hasSuffix(".") ? " " : ". "
        return trimmedDetail + separator + sentence.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) + "."
    }
}

public struct StarlinkTelemetryPresentation: Equatable, Sendable {
    public let state: String
    public let dropRate: String
    public let obstruction: String
    public let downlinkThroughput: String
    public let uplinkThroughput: String
    public let uptime: String
    public let alerts: String?

    public init?(host: HostConfig, telemetry: StarlinkTelemetry?) {
        guard host.method == .starlink,
              let telemetry,
              Self.hasMeaningfulTelemetry(telemetry) else { return nil }
        self.init(telemetry: telemetry)
    }

    public init(telemetry: StarlinkTelemetry) {
        state = telemetry.state ?? "--"
        dropRate = Self.percent(telemetry.popPingDropRate)
        obstruction = Self.percent(telemetry.fractionObstructed)
        downlinkThroughput = Self.throughput(telemetry.downlinkThroughputBps)
        uplinkThroughput = Self.throughput(telemetry.uplinkThroughputBps)
        uptime = Self.uptime(telemetry.uptimeSeconds)
        alerts = telemetry.activeAlerts.isEmpty ? nil : telemetry.activeAlerts.joined(separator: ", ")
    }

    public static func latest(host: HostConfig, samples: [PingResult]) -> Self? {
        guard host.method == .starlink else { return nil }
        let telemetry = samples
            .compactMap { sample -> (Date, StarlinkTelemetry)? in
                sample.metadata.starlink.map { (sample.timestamp, $0) }
            }
            .max { $0.0 < $1.0 }?
            .1
        guard let telemetry else { return nil }
        return Self(host: host, telemetry: telemetry)
    }

    private static func hasMeaningfulTelemetry(_ telemetry: StarlinkTelemetry) -> Bool {
        telemetry.state != nil
            || telemetry.popPingDropRate != nil
            || telemetry.fractionObstructed != nil
            || telemetry.downlinkThroughputBps != nil
            || telemetry.uplinkThroughputBps != nil
            || telemetry.uptimeSeconds != nil
            || !telemetry.activeAlerts.isEmpty
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func throughput(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value / 1_000_000).rounded())) Mbps"
    }

    private static func uptime(_ value: Double?) -> String {
        guard let value else { return "--" }
        let hours = Int(value / 3_600)
        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h"
    }
}
