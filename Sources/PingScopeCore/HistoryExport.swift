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
    public static func write(samples: [PingResult], host: HostConfig, format: HistoryExportFormat, to url: URL) throws {
        // The sandbox extension granted by NSSavePanel covers only the exact
        // path the user chose, so the streaming temp file must not be a sibling
        // of `url` -- the sandboxed App Store build is denied that create. An
        // item-replacement directory is sandbox-legal and lives on the
        // destination volume, which keeps the final replace/move atomic.
        let stagingDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let temporaryURL = stagingDirectory.appendingPathComponent(url.lastPathComponent)
        try writeTemporary(samples: samples, host: host, format: format, to: temporaryURL)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

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
        let header = csvHeader
        let rows = samples.map { csvRow(sample: $0, host: host, formatter: formatter) }
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
            let starlinkSuffix = sample.metadata.starlink.map { "  \($0.noteSummary)" } ?? ""
            if let latency = sample.latency {
                return "\(timestamp)  \(Int(latency.milliseconds.rounded()))ms  OK\(starlinkSuffix)"
            }
            return "\(timestamp)  \(sample.failureReason?.userMessage ?? "Failed")  Failed\(starlinkSuffix)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func csvRow(sample: PingResult, host: HostConfig, formatter: ISO8601DateFormatter) -> String {
        let starlink = sample.metadata.starlink
        var columns: [String] = []
        columns.append(formatter.string(from: sample.timestamp))
        columns.append(host.displayName)
        columns.append(sample.address)
        columns.append(sample.method.rawValue.uppercased())
        columns.append(sample.port.map(String.init) ?? "")
        columns.append(sample.isSuccess ? "OK" : "Failed")
        columns.append(sample.latency.map { String(Int($0.milliseconds.rounded())) } ?? "")
        columns.append(sample.failureReason?.rawValue ?? "")
        columns.append(sample.metadata.note ?? "")
        columns.append(starlink?.state ?? "")
        columns.append(number(starlink?.popPingDropRate))
        columns.append(number(starlink?.downlinkThroughputBps))
        columns.append(number(starlink?.uplinkThroughputBps))
        columns.append(number(starlink?.fractionObstructed))
        columns.append(number(starlink?.last24hObstructedSeconds))
        columns.append(starlink?.activeAlerts.joined(separator: "|") ?? "")
        return columns.map(csvEscape).joined(separator: ",")
    }

    private static func writeTemporary(samples: [PingResult], host: HostConfig, format: HistoryExportFormat, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        switch format {
        case .csv:
            let formatter = ISO8601DateFormatter()
            try handle.writeLine(csvHeader)
            for sample in samples {
                try handle.writeLine(csvRow(sample: sample, host: host, formatter: formatter))
            }
        case .json:
            try handle.write(contentsOf: JSONEncoder.historyEncoder.encode(HistoryExportDocument(host: host, samples: samples)))
        case .text:
            try writeText(samples: samples, host: host, to: handle)
        }
    }

    private static func writeText(samples: [PingResult], host: HostConfig, to handle: FileHandle) throws {
        let formatter = ISO8601DateFormatter()
        try handle.writeLine("PingScope History")
        try handle.writeLine("Host: \(host.displayName)")
        try handle.writeLine("Address: \(host.address)")
        try handle.writeLine("Method: \(host.method.rawValue.uppercased())")
        try handle.writeLine("Samples: \(samples.count)")
        try handle.writeLine("")
        for sample in samples {
            let timestamp = formatter.string(from: sample.timestamp)
            let starlinkSuffix = sample.metadata.starlink.map { "  \($0.noteSummary)" } ?? ""
            if let latency = sample.latency {
                try handle.writeLine("\(timestamp)  \(Int(latency.milliseconds.rounded()))ms  OK\(starlinkSuffix)")
            } else {
                try handle.writeLine("\(timestamp)  \(sample.failureReason?.userMessage ?? "Failed")  Failed\(starlinkSuffix)")
            }
        }
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static var csvHeader: String {
        [
            "timestamp",
            "host",
            "address",
            "method",
            "port",
            "result",
            "latency_ms",
            "failure_reason",
            "note",
            "starlink_state",
            "starlink_drop_rate",
            "starlink_downlink_bps",
            "starlink_uplink_bps",
            "starlink_fraction_obstructed",
            "starlink_last_24h_obstructed_s",
            "starlink_alerts"
        ].joined(separator: ",")
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

private extension FileHandle {
    func writeLine(_ line: String) throws {
        if let data = "\(line)\n".data(using: .utf8) {
            try write(contentsOf: data)
        }
    }
}
