import Foundation
import PingScopeCore

@main
struct PingScopeExportValidate {
    static func main() async throws {
        let arguments = ArgumentParser(arguments: Array(CommandLine.arguments.dropFirst()))
        let databasePath = try arguments.requiredValue(after: "--db")
        let outputDirectoryPath = try arguments.requiredValue(after: "--output-dir")
        let hostID = try UUID(uuidString: arguments.requiredValue(after: "--host-id")).unwrap("Invalid --host-id")
        let displayName = arguments.value(after: "--name") ?? "Export Validation Host"
        let address = arguments.value(after: "--address") ?? "unknown"
        let method = PingMethod(rawValue: arguments.value(after: "--method") ?? "tcp") ?? .tcp
        let port = UInt16(arguments.value(after: "--port") ?? "")
        let rangeSeconds = TimeInterval(arguments.value(after: "--range-seconds") ?? "3600") ?? 3_600

        let databaseURL = URL(fileURLWithPath: databasePath)
        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let store = SQLiteHistoryStore(url: databaseURL)
        let samples = await store.samples(hostID: hostID, since: Date().addingTimeInterval(-rangeSeconds), limit: 10_000)
        guard !samples.isEmpty else {
            throw ValidationError("No samples found for \(hostID) in the selected range")
        }

        let host = HostConfig(id: hostID, displayName: displayName, address: address, method: method, port: port)
        for format in HistoryExportFormat.allCases {
            let data = try HistoryExporter.data(samples: samples, host: host, format: format)
            guard !data.isEmpty else {
                throw ValidationError("\(format.displayName) export was empty")
            }
            let url = outputDirectory.appendingPathComponent("pingscope-export-smoke.\(format.fileExtension)")
            try data.write(to: url, options: .atomic)
            print("\(format.displayName): \(samples.count) samples -> \(url.path)")
        }
    }
}

private struct ArgumentParser {
    var arguments: [String]

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    func requiredValue(after flag: String) throws -> String {
        guard let value = value(after: flag), !value.isEmpty else {
            throw ValidationError("Missing required argument \(flag)")
        }
        return value
    }
}

private struct ValidationError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw ValidationError(message)
        }
        return value
    }
}
