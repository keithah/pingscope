#if os(macOS)
import Foundation
import XCTest
@testable import PingScope
@testable import PingScopeCore
@testable import PingScopeHistoryKit

final class MacHistorySurfaceTests: XCTestCase {
    func testHistoryRangePersistenceDefaultsAndRoundTripsEveryRange() throws {
        let suiteName = "MacHistorySurfaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(defaults.pingScopeMacHistoryRange, .h24)
        defaults.set("invalid", forKey: "pingScopeMacHistoryRange")
        XCTAssertEqual(defaults.pingScopeMacHistoryRange, .h24)

        for range in HistoryRange.allCases {
            defaults.pingScopeMacHistoryRange = range
            XCTAssertEqual(defaults.pingScopeMacHistoryRange, range)
            XCTAssertEqual(defaults.string(forKey: "pingScopeMacHistoryRange"), range.rawValue)
        }
    }

    func testSurfacePresentationUsesSharedHistoryLogicForEveryRange() async throws {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 4_000_000)
        var samples = (0..<600).map { index in
            var sample = PingResult.success(
                hostID: hostID,
                latency: .milliseconds(Double(10 + index % 40)),
                timestamp: now.addingTimeInterval(Double(index - 600) * 5)
            )
            sample.networkInterface = "wifi"
            sample.networkName = "Office Wi-Fi"
            return sample
        }
        var failure = PingResult.failure(
            hostID: hostID,
            reason: .timeout,
            timestamp: now.addingTimeInterval(-10)
        )
        failure.networkInterface = "cellular"
        failure.networkName = "Cellular · 5G"
        samples.append(failure)

        let loader = MacHistorySurfaceLoader()
        let store = MacHistoryTestStore(results: samples)
        for range in HistoryRange.allCases {
            let loaded = await loader.load(
                store: store,
                hostID: hostID,
                range: range,
                now: now
            )
            let presentation = try XCTUnwrap(loaded)
            XCTAssertEqual(presentation.hostID, hostID)
            XCTAssertEqual(presentation.range, range)
            XCTAssertEqual(presentation.metrics.outageCount, 1)
            XCTAssertEqual(presentation.sessions, HistorySession.sessionize(presentation.samples))
            XCTAssertLessThanOrEqual(presentation.chartReduction.buckets.count, 500)
            XCTAssertEqual(presentation.networkTable.rows.map(\.label), ["Cellular · 5G", "Office Wi-Fi"])
        }
    }

    func testSurfaceLoaderDropsSupersededHostAndRangeResult() async throws {
        let oldHostID = UUID()
        let newHostID = UUID()
        let now = Date(timeIntervalSince1970: 5_000_000)
        let oldSample = PingResult.success(hostID: oldHostID, latency: .milliseconds(90), timestamp: now)
        let newSample = PingResult.success(hostID: newHostID, latency: .milliseconds(10), timestamp: now)
        let store = MacSuspendedFirstHistoryStore(first: [oldSample], subsequent: [newSample])
        let loader = MacHistorySurfaceLoader()

        let first = Task { await loader.load(store: store, hostID: oldHostID, range: .h1, now: now) }
        await store.waitUntilSuspended()
        let loadedSecond = await loader.load(store: store, hostID: newHostID, range: .d30, now: now)
        let second = try XCTUnwrap(loadedSecond)
        XCTAssertEqual(second.hostID, newHostID)
        XCTAssertEqual(second.range, .d30)
        await store.resume()
        let superseded = await first.value
        XCTAssertNil(superseded)
    }

    func testMacHistoryStoreRetentionIsThirtyDays() {
        XCTAssertEqual(PingScopeModel.historyRetention, PingHistoryRetention.maximumDuration)
    }

    func testReportPresentationReusesSharedHistoryReportModel() throws {
        let host = HostConfig(id: UUID(), displayName: "Office Gateway", address: "192.0.2.1")
        let now = Date(timeIntervalSince1970: 6_000_000)
        var success = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(12),
            timestamp: now.addingTimeInterval(-60)
        )
        success.networkInterface = "wifi"
        success.networkName = "Office Wi-Fi"
        let failure = PingResult.failure(hostID: host.id, reason: .timeout, timestamp: now)
        let loadResult = PingScopeIOSHistoryLoadResult(
            hostID: host.id,
            range: .d30,
            cutoff: HistoryRange.d30.cutoff(endingAt: now),
            endingAt: now,
            samples: [success, failure],
            chartReduction: HistoryChartReduction(samples: [success, failure]),
            isCollecting: false
        )
        let surface = MacHistorySurfacePresentation(loadResult: loadResult)

        let report = try XCTUnwrap(MacHistoryReportPresentation.make(host: host, surface: surface))
        let shared = HistoryReportPresentation(host: host, range: .d30, samples: surface.samples)

        XCTAssertEqual(report.content, shared)
        XCTAssertEqual(report.content.networkPresentation, HistoryNetworkPresentation(samples: surface.samples))
        XCTAssertEqual(report.content.sessions, HistorySession.sessionize(surface.samples))
    }

    func testReportActionIsDisabledWhileLoadingOrWithoutSamples() {
        let host = HostConfig.defaultInternet
        let now = Date(timeIntervalSince1970: 7_000_000)
        let empty = MacHistorySurfacePresentation(loadResult: PingScopeIOSHistoryLoadResult(
            hostID: host.id,
            range: .h24,
            cutoff: HistoryRange.h24.cutoff(endingAt: now),
            endingAt: now,
            samples: [],
            chartReduction: HistoryChartReduction(samples: []),
            isCollecting: false
        ))

        XCTAssertFalse(MacHistoryReportPresentation.isActionEnabled(isLoading: true, surface: empty))
        XCTAssertFalse(MacHistoryReportPresentation.isActionEnabled(isLoading: false, surface: empty))

        let sample = PingResult.success(hostID: host.id, latency: .milliseconds(8), timestamp: now)
        let populated = MacHistorySurfacePresentation(loadResult: PingScopeIOSHistoryLoadResult(
            hostID: host.id,
            range: .h24,
            cutoff: HistoryRange.h24.cutoff(endingAt: now),
            endingAt: now,
            samples: [sample],
            chartReduction: HistoryChartReduction(samples: [sample]),
            isCollecting: false
        ))
        XCTAssertFalse(MacHistoryReportPresentation.isActionEnabled(isLoading: true, surface: populated))
        XCTAssertTrue(MacHistoryReportPresentation.isActionEnabled(isLoading: false, surface: populated))
    }

    func testReportPreviewUsesExportArtifactAspectRatio() {
        let previewSize = MacHistoryReportRenderer.previewSize(fittingWidth: 720)

        XCTAssertEqual(previewSize.width, 720, accuracy: 0.001)
        XCTAssertEqual(previewSize.height, 600, accuracy: 0.001)
        XCTAssertEqual(
            previewSize.width / previewSize.height,
            MacHistoryReportRenderer.size.width / MacHistoryReportRenderer.size.height,
            accuracy: 0.000_001
        )
    }

    func testThirtyDayRetentionPrunesSamplesOlderThanThirtyDays() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacHistorySurfaceTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SQLiteHistoryStore(url: url, retention: .days(30))
        let hostID = UUID()
        let now = Date()
        let olderThanRetention = now.addingTimeInterval(-31 * 86_400)

        await store.append(.success(hostID: hostID, latency: .milliseconds(20), timestamp: olderThanRetention))
        await store.append(.success(hostID: hostID, latency: .milliseconds(10), timestamp: now))

        let samples = await store.samples(
            hostID: hostID,
            since: olderThanRetention.addingTimeInterval(-1),
            limit: 10
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(try XCTUnwrap(samples.first).timestamp.timeIntervalSince(now), 0, accuracy: 0.001)
    }
}

private final class MacHistoryTestStore: PingHistoryStore, @unchecked Sendable {
    let results: [PingResult]
    init(results: [PingResult]) { self.results = results }
    func append(_ result: PingResult) async {}
    func append(_ results: [PingResult]) async {}
    func appendAndWait(_ results: [PingResult]) async throws {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(results.filter { $0.hostID == hostID && $0.timestamp >= since }.suffix(limit))
    }
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int { 0 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private final class MacSuspendedFirstHistoryStore: PingHistoryStore, @unchecked Sendable {
    private let state: MacSuspendedFirstHistoryState
    init(first: [PingResult], subsequent: [PingResult]) {
        state = MacSuspendedFirstHistoryState(first: first, subsequent: subsequent)
    }
    func waitUntilSuspended() async { await state.waitUntilSuspended() }
    func resume() async { await state.resume() }
    func append(_ result: PingResult) async {}
    func append(_ results: [PingResult]) async {}
    func appendAndWait(_ results: [PingResult]) async throws {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { await state.query() }
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int { 0 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private actor MacSuspendedFirstHistoryState {
    let first: [PingResult]
    let subsequent: [PingResult]
    var count = 0
    var continuation: CheckedContinuation<[PingResult], Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []

    init(first: [PingResult], subsequent: [PingResult]) {
        self.first = first
        self.subsequent = subsequent
    }

    func query() async -> [PingResult] {
        count += 1
        guard count == 1 else { return subsequent }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        continuation?.resume(returning: first)
        continuation = nil
    }
}
#endif
