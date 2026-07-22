import Foundation
import XCTest
@testable import PingScopeCore
@testable import PingScopeHistoryKit
@testable import PingScopeiOS

@MainActor
final class HistoryExportServiceTests: XCTestCase {
    func testImmutableFileWriteOperationLeavesMainActor() async throws {
        let ranOffMainActor = try await HistoryFileWriteOperation.perform {
            !Thread.isMainThread
        }

        XCTAssertTrue(ranOffMainActor)
    }

    func testReportPresentationAuditsEveryPopulatedField() throws {
        let host = HostConfig(id: UUID(), displayName: "Office Gateway", address: "192.0.2.1")
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            PingResult.success(hostID: host.id, latency: .milliseconds(10), timestamp: start),
            PingResult.success(hostID: host.id, latency: .milliseconds(20), timestamp: start.addingTimeInterval(1)),
        ]

        let report = HistoryReportPresentation(host: host, range: .h4, samples: samples)

        XCTAssertEqual(report.brand, "PingScope")
        XCTAssertEqual(report.hostName, "Office Gateway")
        XCTAssertEqual(report.rangeLabel, "4H")
        XCTAssertEqual(report.sampleCount, 2)
        XCTAssertEqual(report.averageMilliseconds, 15)
        XCTAssertEqual(report.minimumMilliseconds, 10)
        XCTAssertEqual(report.p95Milliseconds, 20)
        XCTAssertEqual(report.maximumMilliseconds, 20)
        XCTAssertEqual(report.lossPercent, 0)
        XCTAssertEqual(report.uptimePercent, 100)
        XCTAssertEqual(report.graphPresentation.averageLineSegments.flatMap { $0 }.count, 2)
        XCTAssertEqual(report.networkPresentation.cards.count, 1)
        XCTAssertEqual(report.sessions, HistorySession.sessionize(samples))
    }

    func testEmptyReportDoesNotFabricateMetricValues() {
        let report = HistoryReportPresentation(host: .defaultInternet, range: .h1, samples: [])

        XCTAssertEqual(report.sampleCount, 0)
        XCTAssertNil(report.averageMilliseconds)
        XCTAssertNil(report.minimumMilliseconds)
        XCTAssertNil(report.p95Milliseconds)
        XCTAssertNil(report.maximumMilliseconds)
        XCTAssertNil(report.lossPercent)
        XCTAssertNil(report.uptimePercent)
        XCTAssertTrue(report.graphPresentation.averageLineSegments.isEmpty)
        XCTAssertTrue(report.networkPresentation.cards.isEmpty)
        XCTAssertTrue(report.sessions.isEmpty)
    }

    func testMixedReportUsesHistoryMetricsSemantics() throws {
        let hostID = UUID()
        let samples = [
            PingResult.success(hostID: hostID, latency: .milliseconds(10)),
            PingResult.failure(hostID: hostID, reason: .timeout),
            PingResult.success(hostID: hostID, latency: .milliseconds(20)),
        ]

        let report = HistoryReportPresentation(
            host: HostConfig(id: hostID, displayName: "Mixed", address: "example.com"),
            range: .h24,
            samples: samples
        )

        XCTAssertEqual(report.averageMilliseconds, 15)
        XCTAssertEqual(report.minimumMilliseconds, 10)
        XCTAssertEqual(report.p95Milliseconds, 20)
        XCTAssertEqual(report.maximumMilliseconds, 20)
        XCTAssertEqual(try XCTUnwrap(report.lossPercent), 100.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(report.uptimePercent), 200.0 / 3.0, accuracy: 0.000_001)
    }

    func testAllFailureReportRetainsRealLossAndUptimeWithoutLatencyValues() {
        let hostID = UUID()
        let samples = [
            PingResult.failure(hostID: hostID, reason: .timeout),
            PingResult.failure(hostID: hostID, reason: .networkUnavailable),
        ]

        let report = HistoryReportPresentation(
            host: HostConfig(id: hostID, displayName: "Down", address: "example.com"),
            range: .d7,
            samples: samples
        )

        XCTAssertNil(report.averageMilliseconds)
        XCTAssertNil(report.minimumMilliseconds)
        XCTAssertNil(report.p95Milliseconds)
        XCTAssertNil(report.maximumMilliseconds)
        XCTAssertEqual(report.lossPercent, 100)
        XCTAssertEqual(report.uptimePercent, 0)
        XCTAssertEqual(report.graphPresentation.failureMarkers.reduce(0) { $0 + $1.failureCount }, 2)
    }

    func testReportP95LossAndUptimeMatchChartLensMetrics() {
        let hostID = UUID()
        let samples = (1...20).map {
            PingResult.success(hostID: hostID, latency: .milliseconds(Double($0)))
        } + [PingResult.failure(hostID: hostID, reason: .timeout)]
        let metrics = HistoryMetrics(samples: samples)

        let report = HistoryReportPresentation(
            host: HostConfig(id: hostID, displayName: "Lens", address: "example.com"),
            range: .d30,
            samples: samples
        )

        XCTAssertEqual(report.p95Milliseconds, metrics.p95Milliseconds)
        XCTAssertEqual(report.lossPercent, metrics.lossPercent)
        XCTAssertEqual(report.uptimePercent, metrics.uptimePercent)
    }

    func testPNGAndPDFPlansUseUniqueFilenamesAndExtensions() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = HistoryReportFilePlanner(temporaryDirectory: directory)

        let firstPNG = planner.destination(hostName: "Office Gateway", format: .png)
        let secondPNG = planner.destination(hostName: "Office Gateway", format: .png)
        let pdf = planner.destination(hostName: "Office Gateway", format: .pdf)

        XCTAssertNotEqual(firstPNG.lastPathComponent, secondPNG.lastPathComponent)
        XCTAssertEqual(firstPNG.pathExtension, "png")
        XCTAssertEqual(secondPNG.pathExtension, "png")
        XCTAssertEqual(pdf.pathExtension, "pdf")
    }

    func testReportRenderingFailureIsNonfatalAndLeavesNoSharePayload() async {
        let service = FailingHistoryReportExportService()
        let coordinator = HistoryExportCoordinator(store: nil, service: service)
        let report = HistoryReportPresentation(host: .defaultInternet, range: .h24, samples: [
            PingResult.success(hostID: HostConfig.defaultInternet.id, latency: .milliseconds(12))
        ])

        await coordinator.requestReport(presentation: report, format: .png)

        XCTAssertNil(coordinator.sharePayload)
        XCTAssertNotNil(coordinator.errorMessage)
    }

    func testReportFileLifecycleRemovesPartialDestinationAndReturnsNoPayloadOnWriteFailure() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lifecycle = HistoryReportFileLifecycle(temporaryDirectory: directory)
        var partialDestination: URL?
        var payload: HistorySharePayload?

        XCTAssertThrowsError(
            try {
                payload = try lifecycle.export(hostName: "Partial", format: .pdf) { destination in
                    partialDestination = destination
                    try Data("partial-pdf".utf8).write(to: destination)
                    throw StubExportError.failed
                }
            }()
        )

        XCTAssertNil(payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDestination?.path ?? ""))
    }

    func testSelectedHostAndRangeCutoffReachExportOperation() async throws {
        let store = HistoryExportRecordingStore()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HistoryStructuredExportService(temporaryDirectory: directory)
        let host = HostConfig(id: UUID(), displayName: "Office Gateway", address: "192.0.2.1")
        let now = Date(timeIntervalSince1970: 4_000_000)

        _ = try await service.export(store: store, host: host, range: .d7, format: .csv, now: now)

        let request = try XCTUnwrap(store.requests.first)
        XCTAssertEqual(request.host, host)
        XCTAssertEqual(request.since, HistoryRange.d7.cutoff(endingAt: now))
    }

    func testEveryExportUsesAUniqueFilename() async throws {
        let store = HistoryExportRecordingStore()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HistoryStructuredExportService(temporaryDirectory: directory)

        let first = try await service.export(store: store, host: .defaultInternet, range: .h1, format: .json, now: .now)
        let second = try await service.export(store: store, host: .defaultInternet, range: .h1, format: .json, now: .now)

        XCTAssertNotEqual(first.files.first?.lastPathComponent, second.files.first?.lastPathComponent)
        XCTAssertEqual(first.files.first?.pathExtension, "json")
        XCTAssertEqual(second.files.first?.pathExtension, "json")
    }

    func testCSVJSONAndTextSelectionsReachHistoryStore() async throws {
        let store = HistoryExportRecordingStore()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HistoryStructuredExportService(temporaryDirectory: directory)

        for format in HistoryExportFormat.allCases {
            _ = try await service.export(store: store, host: .defaultInternet, range: .h24, format: format, now: .now)
        }

        XCTAssertEqual(store.requests.map(\.format), [.csv, .json, .text])
        XCTAssertEqual(store.requests.map { $0.url.pathExtension }, ["csv", "json", "txt"])
    }

    func testCompletedActivityDeletesEveryGeneratedFile() async throws {
        let coordinator = makeCoordinator()
        await coordinator.requestExport(host: .defaultInternet, range: .h4, format: .csv, now: .now)
        let files = try XCTUnwrap(coordinator.sharePayload?.files)
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        coordinator.activityDidFinish(completed: true)

        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertNil(coordinator.sharePayload)
    }

    func testCancelledActivityDeletesEveryGeneratedFile() async throws {
        let coordinator = makeCoordinator()
        await coordinator.requestExport(host: .defaultInternet, range: .h4, format: .text, now: .now)
        let files = try XCTUnwrap(coordinator.sharePayload?.files)

        coordinator.activityDidFinish(completed: false)

        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertNil(coordinator.sharePayload)
    }

    func testExportErrorIsNonfatalStateAndDoesNotMutateHistorySelectionOrSamples() async {
        let store = HistoryExportRecordingStore(error: StubExportError.failed)
        let service = HistoryStructuredExportService(temporaryDirectory: temporaryDirectory())
        let coordinator = HistoryExportCoordinator(store: store, service: service)
        let selectedHost = HostConfig(id: UUID(), displayName: "Selected", address: "example.com")
        let selectedRange = HistoryRange.d14
        let presentationState = PingScopeIOSHistoryPresentationState.loading(
            selection: PingScopeIOSHistorySelection(hostID: selectedHost.id, range: selectedRange)
        )
        let samples = [PingResult.success(hostID: selectedHost.id, latency: .milliseconds(12), timestamp: .now)]
        let originalHost = selectedHost
        let originalRange = selectedRange
        let originalPresentationState = presentationState
        let originalSamples = samples

        await coordinator.requestExport(
            host: selectedHost,
            range: selectedRange,
            format: .json,
            now: .now
        )

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertNil(coordinator.sharePayload)
        XCTAssertEqual(selectedHost, originalHost)
        XCTAssertEqual(selectedRange, originalRange)
        XCTAssertEqual(presentationState, originalPresentationState)
        XCTAssertEqual(samples, originalSamples)
    }

    func testOverlappingExportDropsAndDeletesStaleCompletionWithoutReplacingNewerPayload() async throws {
        let store = OverlappingHistoryExportStore()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = HistoryExportCoordinator(
            store: store,
            service: HistoryStructuredExportService(temporaryDirectory: directory)
        )
        let oldHost = HostConfig(id: UUID(), displayName: "Old", address: "old.example")
        let newHost = HostConfig(id: UUID(), displayName: "New", address: "new.example")

        let olderRequest = Task {
            await coordinator.requestExport(host: oldHost, range: .d30, format: .csv, now: .now)
        }
        await store.waitUntilFirstExportIsSuspended()

        await coordinator.requestExport(host: newHost, range: .h1, format: .json, now: .now)
        let newerPayload = try XCTUnwrap(coordinator.sharePayload)
        let newerFile = try XCTUnwrap(newerPayload.files.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newerFile.path))

        await store.resumeFirstExport()
        await olderRequest.value

        let recordedStaleFile = await store.firstExportURL()
        let staleFile = try XCTUnwrap(recordedStaleFile)
        XCTAssertEqual(coordinator.sharePayload, newerPayload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newerFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
    }

    private func makeCoordinator() -> HistoryExportCoordinator {
        let directory = temporaryDirectory()
        return HistoryExportCoordinator(
            store: HistoryExportRecordingStore(),
            service: HistoryStructuredExportService(temporaryDirectory: directory)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class FailingHistoryReportExportService: HistoryExportServicing {
    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload {
        throw StubExportError.failed
    }

    func exportReport(
        presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) async throws -> HistorySharePayload {
        throw StubExportError.failed
    }

    func removeTemporaryFiles(_ files: [URL]) {}
}

private actor OverlappingHistoryExportStore: PingHistoryStore {
    private var firstURL: URL?
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var firstDidSuspend = false
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var exportCount = 0

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func exportSamples(
        host: HostConfig,
        since: Date,
        format: HistoryExportFormat,
        to url: URL
    ) async throws -> Int {
        exportCount += 1
        if exportCount == 1 {
            firstURL = url
            firstDidSuspend = true
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        try Data(host.displayName.utf8).write(to: url)
        return 1
    }

    func waitUntilFirstExportIsSuspended() async {
        if firstDidSuspend { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeFirstExport() {
        firstContinuation?.resume()
        firstContinuation = nil
    }

    func firstExportURL() -> URL? { firstURL }
}

private enum StubExportError: Error {
    case failed
}

private struct RecordedHistoryExport {
    let host: HostConfig
    let since: Date
    let format: HistoryExportFormat
    let url: URL
}

private final class HistoryExportRecordingStore: PingHistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [RecordedHistoryExport] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    var requests: [RecordedHistoryExport] {
        lock.withLock { recordedRequests }
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func exportSamples(
        host: HostConfig,
        since: Date,
        format: HistoryExportFormat,
        to url: URL
    ) async throws -> Int {
        lock.withLock {
            recordedRequests.append(RecordedHistoryExport(host: host, since: since, format: format, url: url))
        }
        if let error { throw error }
        try Data("export".utf8).write(to: url)
        return 1
    }
}
