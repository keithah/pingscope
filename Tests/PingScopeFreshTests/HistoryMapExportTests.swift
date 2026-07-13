import Foundation
import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

@MainActor
final class HistoryMapExportTests: XCTestCase {
    func testPinsPlanContainsProjectedRouteQualityStylesAndFailureGlyph() throws {
        let presentation = makePresentation()
        let plan = HistoryMapDrawingPlan(
            presentation: presentation,
            lens: .pins,
            viewport: .init(x: 0, y: 0, width: 360, height: 180),
            project: { .init(x: $0.longitude + 180, y: 90 - $0.latitude) }
        )

        XCTAssertEqual(plan.lens, .pins)
        XCTAssertEqual(plan.routeSegments.flatMap { $0 }.count, presentation.route.count)
        XCTAssertEqual(plan.points.map(\.quality), [.fast, .moderate, .slow, .failure])
        XCTAssertEqual(plan.points.map(\.failureCue), [.none, .none, .none, .octagonCross])
        XCTAssertTrue(plan.circles.isEmpty)
    }

    func testHeatPlanContainsTranslucentCirclesAndNonColorFailureCue() {
        let presentation = makePresentation()
        let plan = HistoryMapDrawingPlan(
            presentation: presentation,
            lens: .heat,
            viewport: .init(x: -180, y: -90, width: 360, height: 180),
            project: { .init(x: $0.longitude, y: $0.latitude) }
        )

        XCTAssertEqual(plan.lens, .heat)
        XCTAssertTrue(plan.routeSegments.isEmpty)
        XCTAssertTrue(plan.points.isEmpty)
        XCTAssertEqual(plan.circles.map(\.quality), [.fast, .moderate, .slow, .failure])
        XCTAssertTrue(plan.circles.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertEqual(plan.circles.last?.failureCue, .octagonCross)
    }

    func testProjectionCanExcludePointsOutsideVisibleRegion() {
        let plan = HistoryMapDrawingPlan(
            presentation: makePresentation(),
            lens: .pins,
            viewport: .init(x: -122.15, y: 36, width: 1, height: 2),
            project: { .init(x: $0.longitude, y: $0.latitude) }
        )

        XCTAssertEqual(plan.points.count, 2)
        XCTAssertEqual(plan.routeSegments.count, 1)
    }

    func testPlanNeverExceedsBoundedPresentationCaps() {
        let hostID = UUID()
        let samples = (0..<2_000).map { index in
            locatedResult(
                hostID: hostID,
                latency: .milliseconds(Double(index % 120)),
                latitude: 30 + Double(index) * 0.0001,
                longitude: -120 + Double(index) * 0.0001,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
        let presentation = HistoryMapPresentation(samples: samples)
        let plan = HistoryMapDrawingPlan(
            presentation: presentation,
            lens: .pins,
            viewport: .init(x: -180, y: -90, width: 360, height: 180),
            project: { .init(x: $0.longitude, y: $0.latitude) }
        )

        XCTAssertLessThanOrEqual(plan.points.count, HistoryMapPresentation.defaultMaximumPointCount)
        XCTAssertLessThanOrEqual(
            plan.routeSegments.flatMap { $0 }.count,
            HistoryMapPresentation.defaultMaximumRoutePointCount
        )
    }

    func testRouteSegmentCrossingViewportIsClippedAndRetained() {
        let presentation = routePresentation([(5, -5), (5, 15)])
        let plan = HistoryMapDrawingPlan(
            presentation: presentation,
            lens: .pins,
            viewport: .init(x: 0, y: 0, width: 10, height: 10),
            project: { .init(x: $0.longitude, y: $0.latitude) }
        )

        XCTAssertEqual(plan.routeSegments, [[
            .init(position: .init(x: 0, y: 5)),
            .init(position: .init(x: 10, y: 5)),
        ]])
    }

    func testOffscreenNonCrossingPathCreatesRouteBreakInsteadOfFalseConnection() {
        let presentation = routePresentation([(1, 1), (-5, -5), (15, -5), (9, 9)])
        let plan = HistoryMapDrawingPlan(
            presentation: presentation,
            lens: .pins,
            viewport: .init(x: 0, y: 0, width: 10, height: 10),
            project: { .init(x: $0.longitude, y: $0.latitude) }
        )

        XCTAssertEqual(plan.routeSegments.count, 2)
        XCTAssertEqual(plan.routeSegments[0].first?.position, .init(x: 1, y: 1))
        XCTAssertEqual(plan.routeSegments[0].last?.position, .init(x: 0, y: 0))
        XCTAssertEqual(plan.routeSegments[1].last?.position, .init(x: 9, y: 9))
    }

    func testMapExportRequestRetainsSelectedHostRangeLensAndVisibleRegion() async throws {
        let host = HostConfig(id: UUID(), displayName: "Selected", address: "selected.example")
        let presentation = makePresentation()
        let region = HistoryMapExportRegion(
            centerLatitude: 37.2,
            centerLongitude: -122.1,
            latitudeDelta: 0.5,
            longitudeDelta: 0.75
        )
        let request = HistoryMapExportRequest(
            host: host,
            range: .d14,
            lens: .heat,
            presentation: presentation,
            visibleRegion: region
        )
        let service = RecordingMapExportService()
        let coordinator = HistoryExportCoordinator(store: nil, service: service)

        await coordinator.requestMap(request)

        XCTAssertEqual(service.mapRequests, [request])
        XCTAssertNotNil(coordinator.sharePayload)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testMapExportFailureIsNonfatalAndLeavesNoSharePayload() async {
        let service = RecordingMapExportService(error: MapStubError.failed)
        let coordinator = HistoryExportCoordinator(store: nil, service: service)
        await coordinator.requestMap(
            HistoryMapExportRequest(
                host: .defaultInternet,
                range: .h4,
                lens: .pins,
                presentation: makePresentation(),
                visibleRegion: .init(centerLatitude: 0, centerLongitude: 0, latitudeDelta: 1, longitudeDelta: 1)
            )
        )

        XCTAssertNil(coordinator.sharePayload)
        XCTAssertNotNil(coordinator.errorMessage)
    }

    func testCancelledInFlightMapExportDeletesStaleCompletion() async throws {
        let service = SuspendedMapExportService()
        let coordinator = HistoryExportCoordinator(store: nil, service: service)
        let request = HistoryMapExportRequest(
            host: .defaultInternet,
            range: .h24,
            lens: .pins,
            presentation: makePresentation(),
            visibleRegion: .init(centerLatitude: 37, centerLongitude: -122, latitudeDelta: 1, longitudeDelta: 1)
        )
        let task = Task { await coordinator.requestMap(request) }
        await service.waitUntilStarted()

        coordinator.activityDidFinish(completed: false)
        service.resume()
        await task.value

        XCTAssertNil(coordinator.sharePayload)
        XCTAssertEqual(service.removedFiles, [service.outputURL])
    }

    func testTaskCancellationPropagatesAndRemovesPartialMapWithoutPublishing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CancellableMapExportService(directory: directory)
        let coordinator = HistoryExportCoordinator(store: nil, service: service)
        let request = HistoryMapExportRequest(
            host: .defaultInternet,
            range: .h24,
            lens: .pins,
            presentation: makePresentation(),
            visibleRegion: .init(centerLatitude: 37, centerLongitude: -122, latitudeDelta: 1, longitudeDelta: 1)
        )
        let task = Task { await coordinator.requestMap(request) }
        await service.waitUntilPartialFileExists()

        task.cancel()
        await task.value

        XCTAssertTrue(service.observedCancellation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.outputURL.path))
        XCTAssertNil(coordinator.sharePayload)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testCancelledTaskDeletesPayloadReturnedByNoncooperativeService() async {
        let service = NoncooperativeCancelledMapExportService()
        let coordinator = HistoryExportCoordinator(store: nil, service: service)
        let request = HistoryMapExportRequest(
            host: .defaultInternet,
            range: .h24,
            lens: .pins,
            presentation: makePresentation(),
            visibleRegion: .init(centerLatitude: 37, centerLongitude: -122, latitudeDelta: 1, longitudeDelta: 1)
        )
        let task = Task { await coordinator.requestMap(request) }
        await service.waitUntilStarted()

        task.cancel()
        service.returnPayloadDespiteCancellation()
        await task.value

        XCTAssertEqual(service.removedFiles, [service.outputURL])
        XCTAssertNil(coordinator.sharePayload)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testMapFileLifecycleUsesUniqueNamesAndRemovesPartialFileOnFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lifecycle = HistoryMapFileLifecycle(temporaryDirectory: directory)
        let first = try lifecycle.export(hostName: "Office Gateway") { destination in
            try Data("png".utf8).write(to: destination)
        }
        let second = try lifecycle.export(hostName: "Office Gateway") { destination in
            try Data("png".utf8).write(to: destination)
        }

        XCTAssertNotEqual(first.files.first?.lastPathComponent, second.files.first?.lastPathComponent)
        XCTAssertEqual(first.files.first?.pathExtension, "png")
        var partial: URL?
        XCTAssertThrowsError(try lifecycle.export(hostName: "Failure") { destination in
            partial = destination
            try Data("partial".utf8).write(to: destination)
            throw MapStubError.failed
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial?.path ?? ""))
    }

    private func makePresentation() -> HistoryMapPresentation {
        let hostID = UUID()
        return HistoryMapPresentation(samples: [
            locatedResult(hostID: hostID, latency: .milliseconds(10), latitude: 37.0, longitude: -122.0, timestamp: Date(timeIntervalSince1970: 1)),
            locatedResult(hostID: hostID, latency: .milliseconds(30), latitude: 37.1, longitude: -122.1, timestamp: Date(timeIntervalSince1970: 2)),
            locatedResult(hostID: hostID, latency: .milliseconds(81), latitude: 37.2, longitude: -122.2, timestamp: Date(timeIntervalSince1970: 3)),
            PingResult.failure(
                hostID: hostID,
                reason: .timeout,
                timestamp: Date(timeIntervalSince1970: 4),
                location: SampleLocation(latitude: 37.3, longitude: -122.3, horizontalAccuracy: 150)
            ),
        ])
    }

    private func routePresentation(_ coordinates: [(Double, Double)]) -> HistoryMapPresentation {
        let hostID = UUID()
        return HistoryMapPresentation(samples: coordinates.enumerated().map { index, coordinate in
            locatedResult(
                hostID: hostID,
                latency: .milliseconds(10),
                latitude: coordinate.0,
                longitude: coordinate.1,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        })
    }

    private func locatedResult(
        hostID: UUID,
        latency: Duration,
        latitude: Double,
        longitude: Double,
        timestamp: Date
    ) -> PingResult {
        PingResult.success(
            hostID: hostID,
            latency: latency,
            timestamp: timestamp,
            location: SampleLocation(latitude: latitude, longitude: longitude, horizontalAccuracy: 100)
        )
    }
}

@MainActor
private final class RecordingMapExportService: HistoryExportServicing {
    private(set) var mapRequests: [HistoryMapExportRequest] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload {
        throw MapStubError.failed
    }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        mapRequests.append(request)
        if let error { throw error }
        return HistorySharePayload(files: [URL(fileURLWithPath: "/tmp/map.png")])
    }

    func removeTemporaryFiles(_ files: [URL]) {}
}

private enum MapStubError: Error {
    case failed
}

@MainActor
private final class SuspendedMapExportService: HistoryExportServicing {
    let outputURL = URL(fileURLWithPath: "/tmp/suspended-map.png")
    private(set) var removedFiles: [URL] = []
    private var exportContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload { throw MapStubError.failed }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { exportContinuation = $0 }
        return HistorySharePayload(files: [outputURL])
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func resume() {
        exportContinuation?.resume()
        exportContinuation = nil
    }

    func removeTemporaryFiles(_ files: [URL]) {
        removedFiles.append(contentsOf: files)
    }
}

@MainActor
private final class CancellableMapExportService: HistoryExportServicing {
    let outputURL: URL
    private(set) var observedCancellation = false
    private var partialContinuation: CheckedContinuation<Void, Never>?
    private var partialExists = false

    init(directory: URL) {
        outputURL = directory.appendingPathComponent("partial-map.png")
    }

    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload { throw MapStubError.failed }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: outputURL)
        partialExists = true
        partialContinuation?.resume()
        partialContinuation = nil
        do {
            try await Task.sleep(for: .seconds(60))
            return HistorySharePayload(files: [outputURL])
        } catch is CancellationError {
            observedCancellation = true
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
    }

    func waitUntilPartialFileExists() async {
        if partialExists { return }
        await withCheckedContinuation { partialContinuation = $0 }
    }

    func removeTemporaryFiles(_ files: [URL]) {
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

@MainActor
private final class NoncooperativeCancelledMapExportService: HistoryExportServicing {
    let outputURL = URL(fileURLWithPath: "/tmp/noncooperative-cancelled-map.png")
    private(set) var removedFiles: [URL] = []
    private var exportContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload { throw MapStubError.failed }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { exportContinuation = $0 }
        return HistorySharePayload(files: [outputURL])
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func returnPayloadDespiteCancellation() {
        exportContinuation?.resume()
        exportContinuation = nil
    }

    func removeTemporaryFiles(_ files: [URL]) {
        removedFiles.append(contentsOf: files)
    }
}
