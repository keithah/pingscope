import Foundation

public enum HistoryExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json
    case text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .csv: "CSV"
        case .json: "JSON"
        case .text: "Text"
        }
    }

    public var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .json: "json"
        case .text: "txt"
        }
    }
}

public enum HistoryExporter {
    public static func data(samples: [PingResult], host: HostConfig, format: HistoryExportFormat) throws -> Data {
        switch format {
        case .csv:
            return csv(samples: samples, host: host).data(using: .utf8) ?? Data()
        case .json:
            return try JSONEncoder.historyEncoder.encode(HistoryExportDocument(host: host, samples: samples))
        case .text:
            return text(samples: samples, host: host).data(using: .utf8) ?? Data()
        }
    }

    public static func csv(samples: [PingResult], host: HostConfig) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "timestamp,host,address,method,port,result,latency_ms,failure_reason,note"
        let rows = samples.map { sample in
            [
                formatter.string(from: sample.timestamp),
                host.displayName,
                sample.address,
                sample.method.rawValue.uppercased(),
                sample.port.map(String.init) ?? "",
                sample.isSuccess ? "OK" : "Failed",
                sample.latency.map { String(Int($0.milliseconds.rounded())) } ?? "",
                sample.failureReason?.rawValue ?? "",
                sample.metadata.note ?? ""
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func text(samples: [PingResult], host: HostConfig) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "PingScope History",
            "Host: \(host.displayName)",
            "Address: \(host.address)",
            "Method: \(host.method.rawValue.uppercased())",
            "Samples: \(samples.count)",
            ""
        ]
        lines += samples.map { sample in
            let timestamp = formatter.string(from: sample.timestamp)
            if let latency = sample.latency {
                return "\(timestamp)  \(Int(latency.milliseconds.rounded()))ms  OK"
            }
            return "\(timestamp)  \(sample.failureReason?.userMessage ?? "Failed")  Failed"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct HistoryExportDocument: Encodable {
    var generatedAt = Date()
    var host: HostConfig
    var samples: [PingResult]
}

private extension JSONEncoder {
    static var historyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
