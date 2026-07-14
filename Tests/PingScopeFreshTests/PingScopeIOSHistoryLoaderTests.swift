import Foundation
import XCTest
@testable import PingScopeCore
@testable import PingScopeHistoryKit
@testable import PingScopeiOS

final class PingScopeIOSHistoryLoaderTests: XCTestCase {
    func testHistoryRangePersistenceDefaultsAndRoundTripsEveryValidRange() throws {
        let suiteName = "PingScopeIOSHistoryRangeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removeObject(forKey: "pingScopeIOSHistoryRange")
        XCTAssertEqual(defaults.pingScopeIOSHistoryRange, .h24)

        defaults.set("not-a-range", forKey: "pingScopeIOSHistoryRange")
        XCTAssertEqual(defaults.pingScopeIOSHistoryRange, .h24)

        for range in HistoryRange.allCases {
            defaults.pingScopeIOSHistoryRange = range
            XCTAssertEqual(defaults.pingScopeIOSHistoryRange, range)
            XCTAssertEqual(defaults.string(forKey: "pingScopeIOSHistoryRange"), range.rawValue)
        }
    }

    func testHistoryLoaderUsesLatestSamplesWithExactCutoffsAndPerRangeLimits() async {
        let store = HistoryQueryRecordingStore()
        let loader = PingScopeIOSHistoryLoader()
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 3_000_000)

        for range in HistoryRange.allCases {
            _ = await loader.load(store: store, hostID: hostID, range: range, now: now)
        }

        let queries = await store.recordedQueries()
        XCTAssertEqual(queries.count, HistoryRange.allCases.count)
        for (query, range) in zip(queries, HistoryRange.allCases) {
            XCTAssertEqual(query.method, .latestSamples)
            XCTAssertEqual(query.hostID, hostID)
            XCTAssertEqual(query.since, range.cutoff(endingAt: now))
            XCTAssertEqual(query.limit, range.queryLimit)
        }
    }

    func testHistoryLoaderStableSortsAscendingAndAllowsNormalLeadingCadenceTolerance() async {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cutoff = HistoryRange.h1.cutoff(endingAt: now)
        let equalFirst = sample(hostID: hostID, at: cutoff.addingTimeInterval(10), latency: 30)
        let equalSecond = sample(hostID: hostID, at: cutoff.addingTimeInterval(10), latency: 20)
        let latest = sample(hostID: hostID, at: cutoff.addingTimeInterval(20), latency: 10)
        let store = HistoryQueryRecordingStore(results: [latest, equalFirst, equalSecond])

        let result = await PingScopeIOSHistoryLoader().load(
            store: store,
            hostID: hostID,
            range: .h1,
            now: now
        )

        XCTAssertEqual(result?.samples.map(\.id), [equalFirst.id, equalSecond.id, latest.id])
        XCTAssertEqual(result?.hostID, hostID)
        XCTAssertEqual(result?.range, .h1)
        XCTAssertEqual(result?.cutoff, cutoff)
        XCTAssertEqual(result?.endingAt, now)
        XCTAssertEqual(result?.isCollecting, false)
        XCTAssertEqual(result?.chartReduction.buckets.count, 3)

        let empty = await PingScopeIOSHistoryLoader().load(
            store: HistoryQueryRecordingStore(),
            hostID: hostID,
            range: .h1,
            now: now
        )
        XCTAssertEqual(empty?.isCollecting, false)

        let fullWindow = await PingScopeIOSHistoryLoader().load(
            store: HistoryQueryRecordingStore(results: [sample(hostID: hostID, at: cutoff, latency: 5)]),
            hostID: hostID,
            range: .h1,
            now: now
        )
        XCTAssertEqual(fullWindow?.isCollecting, false)
    }

    func testHistoryLoaderCollectingRequiresMeaningfulLeadingGapOrQueryLimit() async {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cutoff = HistoryRange.h1.cutoff(endingAt: now)
        let lateSamples = [
            sample(hostID: hostID, at: cutoff.addingTimeInterval(600), latency: 10),
            sample(hostID: hostID, at: cutoff.addingTimeInterval(610), latency: 11),
            sample(hostID: hostID, at: cutoff.addingTimeInterval(620), latency: 12),
        ]

        let late = await PingScopeIOSHistoryLoader().load(
            store: HistoryQueryRecordingStore(results: lateSamples),
            hostID: hostID,
            range: .h1,
            now: now
        )
        XCTAssertEqual(late?.isCollecting, true)

        let atLimit = (0..<HistoryRange.h1.queryLimit).map { index in
            sample(hostID: hostID, at: cutoff.addingTimeInterval(Double(index)), latency: 10)
        }
        let limited = await PingScopeIOSHistoryLoader().load(
            store: HistoryQueryRecordingStore(results: atLimit),
            hostID: hostID,
            range: .h1,
            now: now
        )
        XCTAssertEqual(limited?.isCollecting, true)
    }

    func testHistoryRefreshPolicyNeverTurnsOperationalRefreshIntoRangedQuery() {
        let selection = PingScopeIOSHistorySelection(hostID: UUID(), range: .d7)

        XCTAssertNil(PingScopeIOSHistoryRangedRefreshPolicy.selection(for: .operational))
        XCTAssertEqual(
            PingScopeIOSHistoryRangedRefreshPolicy.selection(for: .historyVisible(selection)),
            selection
        )
    }

    func testHistoryLoaderDropsSuspendedResultAfterHostAndRangeChange() async throws {
        let oldHostID = UUID()
        let newHostID = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let oldSample = sample(hostID: oldHostID, at: now.addingTimeInterval(-30), latency: 90)
        let newSample = sample(hostID: newHostID, at: now.addingTimeInterval(-20), latency: 10)
        let store = SuspendedFirstHistoryStore(firstResults: [oldSample], subsequentResults: [newSample])
        let loader = PingScopeIOSHistoryLoader()

        let requestA = Task {
            await loader.load(store: store, hostID: oldHostID, range: .h1, now: now)
        }
        await store.waitUntilFirstQueryIsSuspended()

        let requestB = await loader.load(store: store, hostID: newHostID, range: .d7, now: now)
        let publishedB = try XCTUnwrap(requestB)
        XCTAssertEqual(publishedB.hostID, newHostID)
        XCTAssertEqual(publishedB.range, .d7)
        XCTAssertEqual(publishedB.samples.map(\.id), [newSample.id])

        await store.resumeFirstQuery()
        let supersededA = await requestA.value
        XCTAssertNil(supersededA)
    }

    private func sample(hostID: UUID, at timestamp: Date, latency: Double) -> PingResult {
        PingResult.success(hostID: hostID, latency: .milliseconds(latency), timestamp: timestamp)
    }
}

private enum RecordedHistoryQueryMethod: Equatable, Sendable {
    case latestSamples
}

private struct RecordedHistoryQuery: Equatable, Sendable {
    let method: RecordedHistoryQueryMethod
    let hostID: UUID
    let since: Date
    let limit: Int
}

private final class HistoryQueryRecordingStore: PingHistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [RecordedHistoryQuery] = []
    private let results: [PingResult]

    init(results: [PingResult] = []) {
        self.results = results
    }

    func recordedQueries() async -> [RecordedHistoryQuery] {
        lock.withLock { queries }
    }

    func append(_ result: PingResult) async {}
    func append(_ results: [PingResult]) async {}
    func appendAndWait(_ results: [PingResult]) async throws {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        lock.withLock {
            queries.append(RecordedHistoryQuery(method: .latestSamples, hostID: hostID, since: since, limit: limit))
        }
        return results
    }
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int { 0 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private final class SuspendedFirstHistoryStore: PingHistoryStore, @unchecked Sendable {
    private let state: SuspendedFirstHistoryState

    init(firstResults: [PingResult], subsequentResults: [PingResult]) {
        state = SuspendedFirstHistoryState(firstResults: firstResults, subsequentResults: subsequentResults)
    }

    func waitUntilFirstQueryIsSuspended() async { await state.waitUntilFirstQueryIsSuspended() }
    func resumeFirstQuery() async { await state.resumeFirstQuery() }

    func append(_ result: PingResult) async {}
    func append(_ results: [PingResult]) async {}
    func appendAndWait(_ results: [PingResult]) async throws {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        await state.query()
    }
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int { 0 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private actor SuspendedFirstHistoryState {
    private let firstResults: [PingResult]
    private let subsequentResults: [PingResult]
    private var queryCount = 0
    private var firstContinuation: CheckedContinuation<[PingResult], Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(firstResults: [PingResult], subsequentResults: [PingResult]) {
        self.firstResults = firstResults
        self.subsequentResults = subsequentResults
    }

    func query() async -> [PingResult] {
        queryCount += 1
        guard queryCount == 1 else { return subsequentResults }
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilFirstQueryIsSuspended() async {
        if firstContinuation != nil { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func resumeFirstQuery() {
        firstContinuation?.resume(returning: firstResults)
        firstContinuation = nil
    }
}
