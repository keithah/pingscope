import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeIOSHistoryPresentationTests: XCTestCase {
    func testHistoryRangesExposeRawValuesDurationsCutoffsAndQueryLimits() {
        let end = Date(timeIntervalSince1970: 4_000_000)

        XCTAssertEqual(HistoryRange.allCases.map(\.rawValue), ["1H", "4H", "12H", "24H", "7D", "14D", "30D"])
        XCTAssertEqual(HistoryRange.allCases.map(\.duration), [3_600, 14_400, 43_200, 86_400, 604_800, 1_209_600, 2_592_000])
        XCTAssertEqual(HistoryRange.allCases.map { $0.cutoff(endingAt: end) }, HistoryRange.allCases.map { end.addingTimeInterval(-$0.duration) })
        XCTAssertEqual(HistoryRange.allCases.map(\.queryLimit), [2_500, 8_000, 25_000, 50_000, 50_000, 50_000, 50_000])
        XCTAssertEqual(HistoryRange.allCases.map(\.usesLongRangeReduction), [false, false, false, false, true, true, true])
        XCTAssertEqual(HistoryRange.defaultValue, .h24)
    }

    func testHistoryMetricsHandlesEmptyAndSingleSampleWindows() {
        let empty = HistoryMetrics(samples: [])
        XCTAssertNil(empty.averageMilliseconds)
        XCTAssertNil(empty.p95Milliseconds)
        XCTAssertNil(empty.minimumMilliseconds)
        XCTAssertNil(empty.maximumMilliseconds)
        XCTAssertEqual(empty.lossPercent, 0)
        XCTAssertEqual(empty.outageCount, 0)
        XCTAssertEqual(empty.uptimePercent, 100)

        let single = HistoryMetrics(samples: [success(at: 0, latency: 12)])
        XCTAssertEqual(single.averageMilliseconds, 12)
        XCTAssertEqual(single.p95Milliseconds, 12)
        XCTAssertEqual(single.minimumMilliseconds, 12)
        XCTAssertEqual(single.maximumMilliseconds, 12)
        XCTAssertEqual(single.lossPercent, 0)
        XCTAssertEqual(single.outageCount, 0)
        XCTAssertEqual(single.uptimePercent, 100)
    }

    func testHistoryMetricsUsesNearestRankP95AndCountsChronologicalFailureRuns() {
        var samples = (1...20).map { success(at: TimeInterval($0), latency: Double($0)) }
        samples += [failure(at: 31), failure(at: 30), success(at: 32, latency: 5), failure(at: 33)]

        let metrics = HistoryMetrics(samples: samples)

        XCTAssertEqual(metrics.p95Milliseconds, 19)
        XCTAssertEqual(metrics.outageCount, 2)
        XCTAssertEqual(metrics.lossPercent, 12.5)
        XCTAssertEqual(metrics.uptimePercent, 87.5)
    }

    func testHistoryMetricsP95IgnoresFailedLatencies() {
        let failedWithLatency = PingResult(
            hostID: Self.hostID,
            timestamp: date(2),
            latency: .milliseconds(9_000),
            failureReason: .timeout
        )
        let metrics = HistoryMetrics(samples: [success(at: 1, latency: 10), failedWithLatency, success(at: 4, latency: 20)])

        XCTAssertEqual(metrics.p95Milliseconds, 20)
    }

    func testHistoryMetricsClampsUptimeAtZero() {
        let telemetry = StarlinkTelemetry(popPingDropRate: 2)
        let sample = PingResult.failure(
            hostID: Self.hostID,
            reason: .timeout,
            timestamp: date(0),
            metadata: ProbeMetadata(starlink: telemetry)
        )

        XCTAssertEqual(HistoryMetrics(samples: [sample]).uptimePercent, 0)
    }

    func testHistoryNominalIntervalUsesLowerMiddlePositiveDelta() {
        let samples = [success(at: 30, latency: 1), success(at: 0, latency: 1), success(at: 10, latency: 1), success(at: 50, latency: 1), success(at: 80, latency: 1)]

        XCTAssertEqual(HistorySession.nominalInterval(samples: samples), 20)
    }

    func testHistoryNominalIntervalFallsBackWithFewerThanTwoPositiveDeltas() {
        XCTAssertEqual(HistorySession.nominalInterval(samples: []), 60)
        XCTAssertEqual(HistorySession.nominalInterval(samples: [success(at: 0, latency: 1)]), 60)
        XCTAssertEqual(HistorySession.nominalInterval(samples: [success(at: 0, latency: 1), success(at: 10, latency: 1)]), 60)
    }

    func testHistorySessionizationUsesStrictGapBoundaryAndStableChronologicalOrder() {
        let equalFirst = success(at: 0, latency: 11)
        let equalSecond = success(at: 0, latency: 12)
        let boundarySample = success(at: 140, latency: 14)
        let samples = [success(at: 261, latency: 15), equalFirst, success(at: 10, latency: 13), boundarySample, equalSecond, success(at: 20, latency: 13)]

        let sessions = HistorySession.sessionize(samples)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].samples.map(\.id), [equalFirst.id, equalSecond.id, samples[2].id, samples[5].id, boundarySample.id])
        XCTAssertEqual(sessions[0].startDate, date(0))
        XCTAssertEqual(sessions[0].endDate, date(140))
        XCTAssertEqual(sessions[1].startDate, date(261))
    }

    func testHistorySessionIncludesMetricsBoundedSparklineAndRedOutageStatus() {
        var samples = (0..<100).map { success(at: Double($0), latency: Double($0 + 1)) }
        samples[50] = failure(at: 50)

        let session = try! XCTUnwrap(HistorySession.sessionize(samples, sparklineLimit: 20).first)

        XCTAssertEqual(session.samples.count, 100)
        XCTAssertLessThanOrEqual(session.sparklineSamples.count, 20)
        XCTAssertEqual(session.metrics.outageCount, 1)
        XCTAssertTrue(session.hasOutage)
        XCTAssertEqual(session.status, .down)
    }

    func testHistoryChartReductionCreatesBoundedOrderedBucketsAndRetainsStatistics() {
        let samples = (0..<2_000).map { success(at: Double($0), latency: Double(($0 % 4) + 10)) }

        let reduction = HistoryChartReduction(samples: samples, maximumBucketCount: 500)

        XCTAssertEqual(reduction.buckets.count, 500)
        XCTAssertEqual(reduction.buckets.first?.minimum?.latencyMilliseconds, 10)
        XCTAssertEqual(reduction.buckets.first?.average?.latencyMilliseconds, 11.5)
        XCTAssertEqual(reduction.buckets.first?.maximum?.latencyMilliseconds, 13)
        XCTAssertEqual(reduction.buckets.map(\.timestamp), reduction.buckets.map(\.timestamp).sorted())
        XCTAssertEqual(reduction.averageLinePoints.count, 500)
    }

    func testHistoryChartReductionRepresentsEveryFailureBearingBucketWithinCap() {
        var samples = (0..<2_000).map { success(at: Double($0), latency: 20) }
        for index in stride(from: 0, to: samples.count, by: 3) {
            samples[index] = failure(at: Double(index))
        }

        let reduction = HistoryChartReduction(samples: samples, maximumBucketCount: 500)

        XCTAssertLessThanOrEqual(reduction.buckets.count, 500)
        XCTAssertEqual(reduction.buckets.reduce(0) { $0 + $1.failureCount }, samples.filter { !$0.isSuccess }.count)
        XCTAssertTrue(reduction.buckets.filter { $0.failureCount > 0 }.allSatisfy { $0.failureRepresentative != nil })
    }

    func testHistoryChartReductionStableSortsEqualTimestamps() {
        let first = success(at: 1, latency: 1)
        let second = failure(at: 1)
        let third = success(at: 1, latency: 3)

        let reduction = HistoryChartReduction(samples: [first, second, third], maximumBucketCount: 3)

        XCTAssertEqual(reduction.buckets.compactMap(\.sourceRepresentativeID), [first.id, second.id, third.id])
    }

    func testHistoryGraphDataAcceptsExplicitWindow() {
        let start = date(100)
        let end = date(200)
        let data = PingScopeIOSLatencyGraphData(
            samples: [success(at: 99, latency: 1), success(at: 100, latency: 2), success(at: 200, latency: 3), success(at: 201, latency: 4)],
            startDate: start,
            endDate: end
        )

        XCTAssertEqual(data.startDate, start)
        XCTAssertEqual(data.endDate, end)
        XCTAssertEqual(data.points.map(\.latencyMilliseconds), [2, 3])
    }

    func testHistoryPresentationShowsMonitoringFirstEmptyStateWithoutFabricatedMetrics() {
        let result = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h24,
            cutoff: date(0),
            endingAt: date(86_400),
            samples: [],
            chartReduction: HistoryChartReduction(samples: []),
            isCollecting: false
        )

        let presentation = PingScopeIOSHistoryPresentation(loadResult: result)

        XCTAssertEqual(presentation.emptyState?.title, "Start monitoring to build history")
        XCTAssertEqual(presentation.emptyState?.message, "Latency trends and sessions will appear here as samples are collected.")
        XCTAssertEqual(presentation.statistics.map(\.value), ["--", "--", "0%", "0"])
        XCTAssertTrue(presentation.sessions.isEmpty)
        XCTAssertTrue(presentation.graphData.points.isEmpty)
    }

    func testHistoryPresentationFormatsStatisticsAndCollectingState() {
        let samples = [
            success(at: 1_000, latency: 10),
            success(at: 1_010, latency: 20),
            failure(at: 1_020),
            success(at: 1_030, latency: 30),
        ]
        let result = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h1,
            cutoff: date(0),
            endingAt: date(3_600),
            samples: samples,
            chartReduction: HistoryChartReduction(samples: samples),
            isCollecting: true
        )

        let presentation = PingScopeIOSHistoryPresentation(loadResult: result)

        XCTAssertEqual(presentation.statistics.map(\.label), ["Avg", "p95", "Loss", "Outages"])
        XCTAssertEqual(presentation.statistics.map(\.value), ["20 ms", "30 ms", "25%", "1"])
        XCTAssertEqual(presentation.collectingText, "Collecting data for the full 1H window")
        XCTAssertNil(presentation.emptyState)
        XCTAssertEqual(presentation.graphData.startDate, date(0))
        XCTAssertEqual(presentation.graphData.endDate, date(3_600))
    }

    func testHistoryPresentationSessionRowsUseOutageStatusAndMonospacedAverageValue() throws {
        let samples = [
            success(at: 0, latency: 12),
            failure(at: 10),
            success(at: 20, latency: 18),
            success(at: 200, latency: 140),
        ]
        let result = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h1,
            cutoff: date(0),
            endingAt: date(3_600),
            samples: samples,
            chartReduction: HistoryChartReduction(samples: samples),
            isCollecting: false
        )

        let presentation = PingScopeIOSHistoryPresentation(loadResult: result)

        XCTAssertEqual(presentation.sessions.count, 2)
        XCTAssertEqual(presentation.sessions[0].status, .down)
        XCTAssertEqual(presentation.sessions[0].averageText, "15 ms")
        XCTAssertEqual(presentation.sessions[1].status, .degraded)
        XCTAssertEqual(presentation.sessions[1].averageText, "140 ms")
        XCTAssertFalse(presentation.sessions[0].graphData.points.isEmpty)
    }

    func testHistoryGraphPresentationPreservesExtremaAndFailureRepresentativesForRendering() throws {
        let samples = [
            success(at: 10, latency: 10),
            success(at: 20, latency: 100),
            failure(at: 30),
        ]
        let reduction = HistoryChartReduction(samples: samples, maximumBucketCount: 1)
        let loadResult = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .d7,
            cutoff: date(0),
            endingAt: date(604_800),
            samples: samples,
            chartReduction: reduction,
            isCollecting: true
        )
        let graph = PingScopeIOSHistoryPresentation(loadResult: loadResult).graphPresentation

        let bucket = try XCTUnwrap(graph.buckets.first)
        XCTAssertEqual(bucket.minimumMilliseconds, 10)
        XCTAssertEqual(bucket.averageMilliseconds, 55)
        XCTAssertEqual(bucket.maximumMilliseconds, 100)
        XCTAssertEqual(bucket.failureCount, 1)
        XCTAssertEqual(graph.failureMarkers.map(\.timestamp), [date(30)])
        XCTAssertGreaterThanOrEqual(graph.scale.axisMaximumMilliseconds, 100)
        XCTAssertEqual(graph.extremaBand.count, 1)
    }

    func testHistoryGraphPresentationBreaksAverageLineAcrossFailureOnlyBucket() {
        let samples = [
            success(at: 10, latency: 10),
            failure(at: 20),
            success(at: 30, latency: 30),
        ]
        let reduction = HistoryChartReduction(samples: samples, maximumBucketCount: 3)
        let graph = PingScopeIOSHistoryGraphPresentation(reduction: reduction)

        XCTAssertEqual(graph.averageLineSegments.map(\.count), [1, 1])
        XCTAssertEqual(graph.failureMarkers.count, 1)
    }

    func testHistorySessionStatusUsesInjectedHostThresholds() throws {
        let samples = [success(at: 0, latency: 40), success(at: 10, latency: 50)]

        let strict = try XCTUnwrap(HistorySession.sessionize(
            samples,
            thresholds: LatencyThresholds(degradedMilliseconds: 20)
        ).first)
        let tolerant = try XCTUnwrap(HistorySession.sessionize(
            samples,
            thresholds: LatencyThresholds(degradedMilliseconds: 100)
        ).first)

        XCTAssertEqual(strict.status, .degraded)
        XCTAssertEqual(tolerant.status, .healthy)

        let loadResult = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h1,
            cutoff: date(0),
            endingAt: date(3_600),
            samples: samples,
            chartReduction: HistoryChartReduction(samples: samples),
            isCollecting: false
        )
        XCTAssertEqual(
            PingScopeIOSHistoryPresentation(
                loadResult: loadResult,
                thresholds: LatencyThresholds(degradedMilliseconds: 20)
            ).sessions.first?.status,
            .degraded
        )
        XCTAssertEqual(
            PingScopeIOSHistoryPresentation(
                loadResult: loadResult,
                thresholds: LatencyThresholds(degradedMilliseconds: 100)
            ).sessions.first?.status,
            .healthy
        )
    }

    func testHistoryEndpointLabelStyleUsesTimesIntradayAndCompactDatesForLongRanges() {
        XCTAssertEqual(HistoryRange.h1.endpointLabelStyle, .time)
        XCTAssertEqual(HistoryRange.h24.endpointLabelStyle, .compactDateTime)
        XCTAssertEqual(HistoryRange.d7.endpointLabelStyle, .compactDateTime)
        XCTAssertEqual(HistoryRange.d14.endpointLabelStyle, .compactDate)
        XCTAssertEqual(HistoryRange.d30.endpointLabelStyle, .compactDate)
    }

    func testHistoryPresentationResolverHidesSuspendedOldHostAndRangeResults() {
        let oldSelection = PingScopeIOSHistorySelection(hostID: UUID(), range: .h1)
        let newSelection = PingScopeIOSHistorySelection(hostID: UUID(), range: .d7)
        let oldPresentation = PingScopeIOSHistoryPresentation(loadResult: nil)
        let published = PingScopeIOSHistoryPresentationState.loaded(
            selection: oldSelection,
            presentation: oldPresentation
        )

        XCTAssertEqual(
            PingScopeIOSHistoryPresentationResolver.resolve(published, for: newSelection),
            .loading
        )
        XCTAssertEqual(
            PingScopeIOSHistoryPresentationResolver.resolve(published, for: oldSelection),
            .content(oldPresentation)
        )
        XCTAssertEqual(
            PingScopeIOSHistoryPresentationResolver.resolve(.loading(selection: newSelection), for: newSelection),
            .loading
        )
    }

    private static let hostID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func success(at seconds: TimeInterval, latency: Double) -> PingResult {
        PingResult.success(hostID: Self.hostID, latency: .milliseconds(latency), timestamp: date(seconds))
    }

    private func failure(at seconds: TimeInterval) -> PingResult {
        PingResult.failure(hostID: Self.hostID, reason: .timeout, timestamp: date(seconds))
    }
}
