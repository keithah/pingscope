import Foundation
import PingScopeCore

public struct HistoryMapExportRegion: Equatable, Sendable {
    public let centerLatitude: Double
    public let centerLongitude: Double
    public let latitudeDelta: Double
    public let longitudeDelta: Double

    public init(
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    ) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

/// Captures one exact bounded History-map selection. The request intentionally
/// carries no raw samples, so rendering cannot fall back to retained 30-day data.
public struct HistoryMapExportRequest: Equatable, Sendable {
    public let host: HostConfig
    public let range: HistoryRange
    public let lens: HistoryMapLens
    public let presentation: HistoryMapPresentation
    public let visibleRegion: HistoryMapExportRegion

    public init(
        host: HostConfig,
        range: HistoryRange,
        lens: HistoryMapLens,
        presentation: HistoryMapPresentation,
        visibleRegion: HistoryMapExportRegion
    ) {
        self.host = host
        self.range = range
        self.lens = lens
        self.presentation = presentation
        self.visibleRegion = visibleRegion
    }
}

public struct HistoryMapFileLifecycle {
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
        hostName: String,
        write: (URL) throws -> Void
    ) throws -> HistorySharePayload {
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let destination = temporaryDirectory.appendingPathComponent(
            "pingscope-\(slug(hostName))-map-\(UUID().uuidString).png",
            isDirectory: false
        )
        do {
            try write(destination)
            return HistorySharePayload(files: [destination])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func slug(_ value: String) -> String {
        let slug = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "history" : slug
    }
}
