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
        do {
            let writer = BufferedFileWriter(handle: handle)
            switch format {
            case .csv:
                let formatter = ISO8601DateFormatter()
                try writer.writeLine(csvHeader)
                for sample in samples {
                    try writer.writeLine(csvRow(sample: sample, host: host, formatter: formatter))
                }
            case .json:
                try writeJSON(samples: samples, host: host, to: writer)
            case .text:
                try writeText(samples: samples, host: host, to: writer)
            }
            try writer.flush()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private static func writeJSON(samples: [PingResult], host: HostConfig, to output: BufferedFileWriter) throws {
        var writer = HistoryJSONStreamWriter(output: output, encoder: .historyEncoder)
        try writer.beginObject()
        try writer.writeField("generatedAt", Date())
        try writer.writeField("host", host)
        try writer.beginArrayField("samples")
        for sample in samples {
            try writer.writeArrayElement(sample)
        }
        try writer.endArray()
        try writer.endObject()
    }

    private static func writeText(samples: [PingResult], host: HostConfig, to writer: BufferedFileWriter) throws {
        let formatter = ISO8601DateFormatter()
        try writer.writeLine("PingScope History")
        try writer.writeLine("Host: \(host.displayName)")
        try writer.writeLine("Address: \(host.address)")
        try writer.writeLine("Method: \(host.method.rawValue.uppercased())")
        try writer.writeLine("Samples: \(samples.count)")
        try writer.writeLine("")
        for sample in samples {
            let timestamp = formatter.string(from: sample.timestamp)
            let starlinkSuffix = sample.metadata.starlink.map { "  \($0.noteSummary)" } ?? ""
            if let latency = sample.latency {
                try writer.writeLine("\(timestamp)  \(Int(latency.milliseconds.rounded()))ms  OK\(starlinkSuffix)")
            } else {
                try writer.writeLine("\(timestamp)  \(sample.failureReason?.userMessage ?? "Failed")  Failed\(starlinkSuffix)")
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

private final class BufferedFileWriter {
    private let handle: FileHandle
    private let flushThreshold: Int
    private var buffer = Data()

    init(handle: FileHandle, flushThreshold: Int = 64 * 1024) {
        self.handle = handle
        self.flushThreshold = flushThreshold
        buffer.reserveCapacity(flushThreshold)
    }

    func write(contentsOf data: Data) throws {
        buffer.append(data)
        if buffer.count >= flushThreshold {
            try flush()
        }
    }

    func writeLine(_ line: String) throws {
        try write(contentsOf: Data(line.utf8))
        try write(contentsOf: Data("\n".utf8))
    }

    func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

private struct HistoryJSONStreamWriter {
    private let output: BufferedFileWriter
    private let encoder: JSONEncoder
    private var objectFieldCount = 0
    private var arrayElementCount = 0

    init(output: BufferedFileWriter, encoder: JSONEncoder) {
        self.output = output
        self.encoder = encoder
    }

    mutating func beginObject() throws {
        try output.writeLine("{")
    }

    mutating func writeField<Value: Encodable>(_ name: String, _ value: Value) throws {
        if objectFieldCount > 0 {
            try output.writeLine(",")
        }
        try output.write(contentsOf: Data("  ".utf8))
        try output.write(contentsOf: JSONEncoder.fieldNameEncoder.encode(name))
        try output.write(contentsOf: Data(" : ".utf8))
        try output.write(contentsOf: try encoder.encode(value))
        objectFieldCount += 1
    }

    mutating func beginArrayField(_ name: String) throws {
        if objectFieldCount > 0 {
            try output.writeLine(",")
        }
        try output.write(contentsOf: Data("  ".utf8))
        try output.write(contentsOf: JSONEncoder.fieldNameEncoder.encode(name))
        try output.writeLine(" : [")
        objectFieldCount += 1
        arrayElementCount = 0
    }

    mutating func writeArrayElement<Value: Encodable>(_ value: Value) throws {
        if arrayElementCount > 0 {
            try output.writeLine(",")
        }
        try output.write(contentsOf: try encoder.encode(value))
        arrayElementCount += 1
    }

    mutating func endArray() throws {
        if arrayElementCount > 0 {
            try output.writeLine("")
        }
        try output.write(contentsOf: Data("  ]".utf8))
    }

    mutating func endObject() throws {
        try output.writeLine("")
        try output.writeLine("}")
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

    static var fieldNameEncoder: JSONEncoder {
        JSONEncoder()
    }
}
