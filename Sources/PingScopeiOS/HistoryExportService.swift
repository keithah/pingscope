import Combine
import Foundation
import PingScopeCore

public struct HistorySharePayload: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let files: [URL]

    public init(id: UUID = UUID(), files: [URL]) {
        self.id = id
        self.files = files
    }
}

/// Creates and removes structured History exports. Platform presentation stays
/// in the app target so UIKit never leaks into PingScopeCore.
@MainActor
public protocol HistoryExportServicing: AnyObject {
    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload

    func exportReport(
        presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) async throws -> HistorySharePayload

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload

    func removeTemporaryFiles(_ files: [URL])
}

public enum HistoryReportExportError: LocalizedError {
    case renderingUnavailable

    public var errorDescription: String? {
        "Report rendering is unavailable."
    }
}

public extension HistoryExportServicing {
    func exportReport(
        presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) async throws -> HistorySharePayload {
        throw HistoryReportExportError.renderingUnavailable
    }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        throw HistoryReportExportError.renderingUnavailable
    }
}

@MainActor
public final class HistoryStructuredExportService: HistoryExportServicing {
    private let fileManager: FileManager
    private let temporaryDirectory: URL

    public init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    public func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload {
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(host: host, format: format)
        do {
            _ = try await store.exportSamples(
                host: host,
                since: range.cutoff(endingAt: now),
                format: format,
                to: destination
            )
            return HistorySharePayload(files: [destination])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func removeTemporaryFiles(_ files: [URL]) {
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func uniqueDestination(host: HostConfig, format: HistoryExportFormat) -> URL {
        let hostSlug = host.displayName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = hostSlug.isEmpty ? "history" : hostSlug
        let filename = "pingscope-\(prefix)-\(UUID().uuidString).\(format.fileExtension)"
        return temporaryDirectory.appendingPathComponent(filename, isDirectory: false)
    }
}

/// Holds only transient sharing state. History selection and loaded samples stay
/// outside this coordinator, so export failures cannot replace either one.
@MainActor
public final class HistoryExportCoordinator: ObservableObject {
    @Published public private(set) var sharePayload: HistorySharePayload?
    @Published public private(set) var errorMessage: String?

    private let store: (any PingHistoryStore)?
    private let service: any HistoryExportServicing
    private var requestGeneration: UInt64 = 0

    public init(
        store: (any PingHistoryStore)?,
        service: (any HistoryExportServicing)? = nil
    ) {
        self.store = store
        self.service = service ?? HistoryStructuredExportService()
    }

    public func requestExport(
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date = Date()
    ) async {
        requestGeneration &+= 1
        let generation = requestGeneration
        errorMessage = nil
        if let existingFiles = sharePayload?.files {
            service.removeTemporaryFiles(existingFiles)
            sharePayload = nil
        }
        guard let store else {
            errorMessage = "History storage is unavailable. Monitoring can continue normally."
            return
        }
        do {
            let payload = try await service.export(
                store: store,
                host: host,
                range: range,
                format: format,
                now: now
            )
            guard generation == requestGeneration else {
                service.removeTemporaryFiles(payload.files)
                return
            }
            sharePayload = payload
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = "Couldn’t export History. \(error.localizedDescription)"
        }
    }

    public func requestReport(
        presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) async {
        requestGeneration &+= 1
        let generation = requestGeneration
        errorMessage = nil
        if let existingFiles = sharePayload?.files {
            service.removeTemporaryFiles(existingFiles)
            sharePayload = nil
        }
        do {
            let payload = try await service.exportReport(
                presentation: presentation,
                format: format
            )
            guard generation == requestGeneration else {
                service.removeTemporaryFiles(payload.files)
                return
            }
            sharePayload = payload
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = "Couldn’t export History report. \(error.localizedDescription)"
        }
    }

    public func requestMap(_ request: HistoryMapExportRequest) async {
        requestGeneration &+= 1
        let generation = requestGeneration
        errorMessage = nil
        if let existingFiles = sharePayload?.files {
            service.removeTemporaryFiles(existingFiles)
            sharePayload = nil
        }
        do {
            let payload = try await service.exportMap(request: request)
            guard !Task.isCancelled else {
                service.removeTemporaryFiles(payload.files)
                return
            }
            guard generation == requestGeneration else {
                service.removeTemporaryFiles(payload.files)
                return
            }
            sharePayload = payload
        } catch {
            guard generation == requestGeneration else { return }
            if error is CancellationError { return }
            errorMessage = "Couldn’t export annotated map. \(error.localizedDescription)"
        }
    }

    public func activityDidFinish(completed: Bool) {
        requestGeneration &+= 1
        if let payload = sharePayload {
            service.removeTemporaryFiles(payload.files)
        }
        sharePayload = nil
    }

    public func dismissError() {
        errorMessage = nil
    }
}
