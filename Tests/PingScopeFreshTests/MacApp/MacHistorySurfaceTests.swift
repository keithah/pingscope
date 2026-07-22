#if os(macOS)
import Foundation
import XCTest
@testable import PingScope
@testable import PingScopeCore
@testable import PingScopeHistoryKit

final class MacHistorySurfaceTests: XCTestCase {
    @MainActor
    func testHistorySurfaceModelAcceptsControlledLoadingDependencies() {
        let host = HostConfig(id: UUID(), displayName: "Controlled", address: "controlled.example.com")
        let store = MacHistoryTestStore(results: [])
        let loader = MacControlledHistorySurfaceLoader()

        let model = PingScopeModel(
            historySurfaceStore: store,
            historySurfaceLoader: loader,
            configuredHosts: [host],
            primaryHostID: host.id
        )

        XCTAssertEqual(model.historySurfaceHost?.id, host.id)
    }

    @MainActor
    func testHistorySurfaceLoadingFlagClearsWhenHostRemovedMidLoad() async {
        let host = HostConfig(id: UUID(), displayName: "Old", address: "old.example.com")
        let replacement = HostConfig(id: UUID(), displayName: "New", address: "new.example.com")
        let loader = MacControlledHistorySurfaceLoader()
        let model = PingScopeModel(
            historySurfaceStore: MacHistoryTestStore(results: []),
            historySurfaceLoader: loader,
            configuredHosts: [host],
            primaryHostID: host.id
        )
        model.historySurfaceHostID = host.id
        model.historySurfaceRange = .h1

        model.refreshHistorySurface()
        let task = model.historySurfaceTask
        await loader.waitForRequestCount(1)
        model.replaceConfiguredHostsForTesting([replacement], primaryHostID: replacement.id)
        await loader.completeRequest(
            at: 0,
            with: makeHistorySurface(hostID: host.id, range: .h1, latencyMilliseconds: 80)
        )
        await task?.value

        XCTAssertFalse(model.isLoadingHistorySurface)
        XCTAssertNil(model.historySurfacePresentation)
    }

    @MainActor
    func testHistorySurfaceLoadingFlagClearsWhenRangeChangesMidLoad() async {
        let host = HostConfig(id: UUID(), displayName: "Range", address: "range.example.com")
        let loader = MacControlledHistorySurfaceLoader()
        let model = PingScopeModel(
            historySurfaceStore: MacHistoryTestStore(results: []),
            historySurfaceLoader: loader,
            configuredHosts: [host],
            primaryHostID: host.id
        )
        model.historySurfaceHostID = host.id
        model.historySurfaceRange = .h1

        model.refreshHistorySurface()
        let firstTask = model.historySurfaceTask
        await loader.waitForRequestCount(1)

        model.historySurfaceRange = .d30
        model.refreshHistorySurface()
        let secondTask = model.historySurfaceTask
        await loader.waitForRequestCount(2)

        await loader.completeRequest(
            at: 0,
            with: makeHistorySurface(hostID: host.id, range: .h1, latencyMilliseconds: 80)
        )
        await firstTask?.value
        XCTAssertTrue(model.isLoadingHistorySurface)
        XCTAssertNil(model.historySurfacePresentation)

        let newer = makeHistorySurface(hostID: host.id, range: .d30, latencyMilliseconds: 12)
        await loader.completeRequest(at: 1, with: newer)
        await secondTask?.value

        XCTAssertFalse(model.isLoadingHistorySurface)
        XCTAssertEqual(model.historySurfacePresentation, newer)
    }

    @MainActor
    func testSupersededHistoryLoadDoesNotOverwriteNewerPresentation() async {
        let host = HostConfig(id: UUID(), displayName: "Overlap", address: "overlap.example.com")
        let loader = MacControlledHistorySurfaceLoader()
        let model = PingScopeModel(
            historySurfaceStore: MacHistoryTestStore(results: []),
            historySurfaceLoader: loader,
            configuredHosts: [host],
            primaryHostID: host.id
        )
        model.historySurfaceHostID = host.id
        model.historySurfaceRange = .h24

        model.refreshHistorySurface()
        let firstTask = model.historySurfaceTask
        await loader.waitForRequestCount(1)
        model.refreshHistorySurface()
        let secondTask = model.historySurfaceTask
        await loader.waitForRequestCount(2)

        let newer = makeHistorySurface(hostID: host.id, range: .h24, latencyMilliseconds: 9)
        await loader.completeRequest(at: 1, with: newer)
        await secondTask?.value
        XCTAssertFalse(model.isLoadingHistorySurface)
        XCTAssertEqual(model.historySurfacePresentation, newer)

        await loader.completeRequest(
            at: 0,
            with: makeHistorySurface(hostID: host.id, range: .h24, latencyMilliseconds: 90)
        )
        await firstTask?.value

        XCTAssertFalse(model.isLoadingHistorySurface)
        XCTAssertEqual(model.historySurfacePresentation, newer)
    }

    @MainActor
    func testStoppingModelClearsHistorySurfaceLoadingFlag() async {
        let host = HostConfig(id: UUID(), displayName: "Stop", address: "stop.example.com")
        let loader = MacControlledHistorySurfaceLoader()
        let model = PingScopeModel(
            historySurfaceStore: MacHistoryTestStore(results: []),
            historySurfaceLoader: loader,
            configuredHosts: [host],
            primaryHostID: host.id
        )

        model.refreshHistorySurface()
        let task = model.historySurfaceTask
        await loader.waitForRequestCount(1)
        model.stop()

        XCTAssertFalse(model.isLoadingHistorySurface)

        await loader.completeRequest(at: 0, with: nil)
        await task?.value
    }

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

    func testWeeklyDigestLoadsTheEntireSevenDayWindowBeyondRowCap() async throws {
        let host = HostConfig(id: UUID(), displayName: "High rate", address: "example.com")
        let now = Date(timeIntervalSince1970: 8_000_000)
        let samples = (0...50_000).map { index in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(10),
                timestamp: now.addingTimeInterval(-Double(index))
            )
        }

        let loadedOptional = await MacHistorySurfaceLoader().load(
            store: MacHistoryTestStore(results: samples),
            hostID: host.id,
            range: .h1,
            host: host,
            allHosts: [host],
            now: now
        )
        let loaded = try XCTUnwrap(loadedOptional)

        XCTAssertEqual(loaded.weeklyDigest?.sampleCount, samples.count)
    }

    func testSurfaceLoaderReusesWeeklyRowsAndQueriesUncoveredTailAcrossLaterRangeChange() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cached", address: "cached.example.com")
        let now = Date(timeIntervalSince1970: 8_500_000)
        let samples = [PingResult.success(
            hostID: host.id,
            latency: .milliseconds(14),
            timestamp: now.addingTimeInterval(-30)
        )]
        let store = MacDigestRecordingHistoryStore(results: samples)
        let loader = MacHistorySurfaceLoader()

        let first = await loader.load(
            store: store,
            hostID: host.id,
            range: .h1,
            host: host,
            allHosts: [host],
            now: now
        )
        let second = await loader.load(
            store: store,
            hostID: host.id,
            range: .d30,
            host: host,
            allHosts: [host],
            now: now.addingTimeInterval(1)
        )

        XCTAssertEqual(first?.weeklyDigest?.sampleCount, second?.weeklyDigest?.sampleCount)
        XCTAssertEqual(second?.weeklyDigest?.endDate, now.addingTimeInterval(1))
        let weeklyDigestQueryCount = await store.weeklyDigestQueryCount()
        let latestQueryCount = await store.latestQueryCount()
        XCTAssertEqual(weeklyDigestQueryCount, 2)
        XCTAssertEqual(latestQueryCount, 2)
    }

    @MainActor
    func testHistoryWindowFirstAppearanceTriggersPreparationOnlyOnce() {
        var lifecycle = MacHistoryWindowLoadLifecycle()

        XCTAssertTrue(lifecycle.consumeFirstAppearance())
        XCTAssertFalse(lifecycle.consumeFirstAppearance())
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

    func testMacHistoryAndReportExposeCapturedLocationsFromSharedPresentation() throws {
        let host = HostConfig(id: UUID(), displayName: "Travel Gateway", address: "192.0.2.20")
        let now = Date(timeIntervalSince1970: 6_500_000)
        let located = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(18),
            timestamp: now,
            location: SampleLocation(
                latitude: 37.3317,
                longitude: -122.0301,
                horizontalAccuracy: 12,
                networkName: "Office Wi-Fi",
                networkInterface: "wifi"
            )
        )
        let unlocated = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(22),
            timestamp: now.addingTimeInterval(5)
        )
        let loadResult = PingScopeIOSHistoryLoadResult(
            hostID: host.id,
            range: .h24,
            cutoff: HistoryRange.h24.cutoff(endingAt: now.addingTimeInterval(5)),
            endingAt: now.addingTimeInterval(5),
            samples: [located, unlocated],
            chartReduction: HistoryChartReduction(samples: [located, unlocated]),
            isCollecting: false
        )

        let surface = MacHistorySurfacePresentation(loadResult: loadResult, host: host)
        let report = try XCTUnwrap(MacHistoryReportPresentation.make(host: host, surface: surface))

        XCTAssertEqual(surface.mapPresentation.points.count, 1)
        XCTAssertEqual(surface.mapPresentation.points.first?.latitude, 37.3317)
        XCTAssertEqual(report.content.locationPresentation.locatedSampleCount, 1)
        XCTAssertEqual(report.content.locationPresentation.totalSampleCount, 2)
        XCTAssertEqual(report.content.locationPresentation.latestCoordinateText, "37.3317, -122.0301")
        XCTAssertEqual(report.content.locationPresentation.latestAccuracyText, "±12 m")
        XCTAssertEqual(report.content.locationPresentation.networkLabels, ["Office Wi-Fi"])
    }

    func testHistoryReportReusesPrecomputedMapSummaryForLocationLabels() {
        let host = HostConfig(id: UUID(), displayName: "Travel Gateway", address: "192.0.2.20")
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(18),
            location: SampleLocation(
                latitude: 37.3317,
                longitude: -122.0301,
                networkName: "Original Network"
            )
        )
        let summary = HistoryMapSummary(
            bestLatencyMilliseconds: 18,
            worstLatencyMilliseconds: 18,
            networkLabels: ["Precomputed Network"],
            worstRenderedPoint: nil
        )

        let report = HistoryReportPresentation(
            host: host,
            range: .h24,
            samples: [sample],
            mapSummary: summary
        )

        XCTAssertEqual(report.locationPresentation.networkLabels, ["Precomputed Network"])
    }

    func testHistoryReportBuildsLocationLabelsWithoutPrecomputedMapSummary() {
        let host = HostConfig(id: UUID(), displayName: "Travel Gateway", address: "192.0.2.20")
        let location = SampleLocation(
            latitude: 37.3317,
            longitude: -122.0301,
            networkName: "Office Wi-Fi",
            networkInterface: "wifi"
        )!
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(18),
            location: location
        )

        let report = HistoryReportPresentation(host: host, range: .h24, samples: [sample])

        XCTAssertEqual(report.locationPresentation.networkLabels, ["Office Wi-Fi"])
    }

    func testHistoryLocationAccuracyTextRejectsNonFiniteAndOversizedValues() {
        XCTAssertNil(HistoryLocationPresentation.accuracyText(for: .nan))
        XCTAssertNil(HistoryLocationPresentation.accuracyText(for: .infinity))
        XCTAssertNil(HistoryLocationPresentation.accuracyText(for: -.infinity))
        XCTAssertNil(HistoryLocationPresentation.accuracyText(for: .greatestFiniteMagnitude))
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

    func testToolbarSpinnerOnlyAppearsForInitialHistoryLoadWithoutPresentation() {
        let host = HostConfig.defaultInternet
        let populated = makeHistorySurface(hostID: host.id, range: .h24, latencyMilliseconds: 8)

        XCTAssertTrue(MacHistoryLoadingPresentation.showsToolbarSpinner(
            isLoading: true,
            surface: nil
        ))
        XCTAssertFalse(MacHistoryLoadingPresentation.showsToolbarSpinner(
            isLoading: true,
            surface: populated
        ))
        XCTAssertFalse(MacHistoryLoadingPresentation.showsToolbarSpinner(
            isLoading: false,
            surface: nil
        ))
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

private actor MacControlledHistorySurfaceLoader: MacHistorySurfaceLoading {
    private var requestCount = 0
    private var completions: [CheckedContinuation<MacHistorySurfacePresentation?, Never>?] = []
    private var requestCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func load(
        store: any PingHistoryStore,
        hostID: UUID,
        range: HistoryRange,
        host: HostConfig?,
        allHosts: [HostConfig],
        now: Date
    ) async -> MacHistorySurfacePresentation? {
        requestCount += 1
        requestCountWaiters.removeAll { waiter in
            guard requestCount >= waiter.count else { return false }
            waiter.continuation.resume()
            return true
        }
        return await withCheckedContinuation { continuation in
            completions.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append((count, continuation))
        }
    }

    func completeRequest(at index: Int, with presentation: MacHistorySurfacePresentation?) {
        completions[index]?.resume(returning: presentation)
        completions[index] = nil
    }
}

private func makeHistorySurface(
    hostID: UUID,
    range: HistoryRange,
    latencyMilliseconds: Double
) -> MacHistorySurfacePresentation {
    let now = Date(timeIntervalSince1970: 9_000_000 + latencyMilliseconds)
    let sample = PingResult.success(
        hostID: hostID,
        latency: .milliseconds(latencyMilliseconds),
        timestamp: now
    )
    return MacHistorySurfacePresentation(loadResult: PingScopeIOSHistoryLoadResult(
        hostID: hostID,
        range: range,
        cutoff: range.cutoff(endingAt: now),
        endingAt: now,
        samples: [sample],
        chartReduction: HistoryChartReduction(samples: [sample]),
        isCollecting: false
    ))
}

private final class MacDigestRecordingHistoryStore: PingHistoryStore, @unchecked Sendable {
    private let results: [PingResult]
    private let counters = MacDigestRecordingCounters()

    init(results: [PingResult]) {
        self.results = results
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        await counters.recordLatestQuery()
        return Array(results.filter { $0.hostID == hostID && $0.timestamp >= since }.suffix(limit))
    }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        await counters.recordWeeklyDigestQuery()
        let included = Set(hostIDs)
        return results.filter {
            included.contains($0.hostID) && $0.timestamp >= since && $0.timestamp <= through
        }.map(HistoryWeeklyDigestSample.init)
    }
    func historyRevision() async -> UInt64 { 1 }
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int { 0 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func weeklyDigestQueryCount() async -> Int { await counters.weeklyDigestQueryCount }
    func latestQueryCount() async -> Int { await counters.latestQueryCount }
}

private actor MacDigestRecordingCounters {
    private(set) var weeklyDigestQueryCount = 0
    private(set) var latestQueryCount = 0

    func recordWeeklyDigestQuery() { weeklyDigestQueryCount += 1 }
    func recordLatestQuery() { latestQueryCount += 1 }
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
