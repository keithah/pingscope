import Foundation

public enum HistoryReportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case pdf

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.uppercased()
    }

    public var fileExtension: String { rawValue }
}

public struct HistoryReportFilePlanner: Sendable {
    public let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func destination(hostName: String, format: HistoryReportFormat) -> URL {
        let slug = hostName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = slug.isEmpty ? "history" : slug
        return temporaryDirectory.appendingPathComponent(
            "pingscope-\(prefix)-\(UUID().uuidString).\(format.fileExtension)",
            isDirectory: false
        )
    }
}

/// Owns the platform-neutral temporary-file transaction around report rendering.
/// The caller supplies rendering/writing so UIKit remains in the app target.
public struct HistoryReportFileLifecycle {
    private let fileManager: FileManager
    private let planner: HistoryReportFilePlanner

    public init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.planner = HistoryReportFilePlanner(temporaryDirectory: temporaryDirectory)
    }

    public func export(
        hostName: String,
        format: HistoryReportFormat,
        write: (URL) throws -> Void
    ) throws -> HistorySharePayload {
        try fileManager.createDirectory(
            at: planner.temporaryDirectory,
            withIntermediateDirectories: true
        )
        let destination = planner.destination(hostName: hostName, format: format)
        do {
            try write(destination)
            return HistorySharePayload(files: [destination])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func exportAsync(
        hostName: String,
        format: HistoryReportFormat,
        write: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> HistorySharePayload {
        try fileManager.createDirectory(
            at: planner.temporaryDirectory,
            withIntermediateDirectories: true
        )
        let destination = planner.destination(hostName: hostName, format: format)
        do {
            try await write(destination)
            return HistorySharePayload(files: [destination])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }
}

public enum HistoryFileWriteOperation {
    public static func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: .utility, operation: operation).value
    }

    public static func write(_ data: Data, to destination: URL) async throws {
        try await perform {
            try data.write(to: destination, options: .atomic)
        }
    }
}
