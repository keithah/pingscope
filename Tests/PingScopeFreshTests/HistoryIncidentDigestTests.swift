import XCTest
import PingScopeCore
@testable import PingScopeHistoryKit

final class HistoryIncidentDigestTests: XCTestCase {
    func testIncidentLogDerivesClosedOngoingBackToBackAndSingleSampleSpans() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            success(hostID, at: start, latency: 12),
            failure(hostID, at: start.addingTimeInterval(10)),
            failure(hostID, at: start.addingTimeInterval(20)),
            success(hostID, at: start.addingTimeInterval(30), latency: 25),
            failure(hostID, at: start.addingTimeInterval(40)),
            success(hostID, at: start.addingTimeInterval(50), latency: 18),
            failure(hostID, at: start.addingTimeInterval(60))
        ]

        let log = HistoryIncidentLog(samples: samples, endingAt: start.addingTimeInterval(90))

        XCTAssertEqual(log.incidents.count, 3)
        XCTAssertEqual(log.incidents[0].startDate, start.addingTimeInterval(10))
        XCTAssertEqual(log.incidents[0].endDate, start.addingTimeInterval(30))
        XCTAssertEqual(log.incidents[0].duration, 20)
        XCTAssertEqual(log.incidents[0].sampleCount, 2)
        XCTAssertEqual(log.incidents[1].duration, 10)
        XCTAssertEqual(log.incidents[1].sampleCount, 1)
        XCTAssertNil(log.incidents[2].endDate)
        XCTAssertEqual(log.incidents[2].duration, 30)
        XCTAssertEqual(log.incidents[2].sampleCount, 1)
    }

    func testIncidentLogIsStableForUnsortedInputAndCarriesOnsetDiagnosisAndWorstLatency() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        let onset = PingResult(
            hostID: hostID,
            timestamp: start,
            latency: .milliseconds(150),
            failureReason: .timeout
        )
        let later = failure(hostID, at: start.addingTimeInterval(5))
        let recovery = success(hostID, at: start.addingTimeInterval(10), latency: 20)
        let diagnosis = NetworkPerspectiveDiagnosis(
            scope: .upstream,
            title: "Internet path unavailable",
            detail: "Upstream targets failed.",
            faultTier: .upstream
        )

        let log = HistoryIncidentLog(
            samples: [recovery, later, onset],
            endingAt: recovery.timestamp,
            diagnosesBySampleID: [onset.id: diagnosis]
        )

        let incident = try XCTUnwrap(log.incidents.first)
        XCTAssertEqual(incident.startDate, start)
        XCTAssertEqual(incident.endDate, recovery.timestamp)
        XCTAssertEqual(incident.worstLatencyMilliseconds, 150)
        XCTAssertEqual(incident.onsetDiagnosisScope, .upstream)
        XCTAssertEqual(incident.onsetFaultTier, .upstream)
    }

    func testIncidentLogHandlesEmptyAndNoIncidentSamples() {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 3_000)
        XCTAssertEqual(HistoryIncidentLog(samples: [], endingAt: now).incidents, [])
        XCTAssertEqual(
            HistoryIncidentLog(samples: [success(hostID, at: now, latency: 9)], endingAt: now).incidents,
            []
        )
    }

    func testIncidentLogReusesNetworkPerspectiveDiagnoserAtOnset() throws {
        let at = Date(timeIntervalSince1970: 4_000)
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let gateway = HostConfig(
            displayName: "Gateway",
            address: "192.168.1.1",
            tier: .localGateway,
            thresholds: thresholds
        )
        let internet = HostConfig(
            displayName: "Internet",
            address: "1.1.1.1",
            tier: .upstream,
            thresholds: thresholds
        )
        let gatewayFailure = failure(gateway.id, at: at)
        let internetFailure = failure(internet.id, at: at)

        let log = HistoryIncidentLog(
            samples: [gatewayFailure],
            host: gateway,
            allHosts: [gateway, internet],
            samplesByHost: [gateway.id: [gatewayFailure], internet.id: [internetFailure]],
            endingAt: at.addingTimeInterval(10)
        )

        XCTAssertEqual(try XCTUnwrap(log.incidents.first).onsetDiagnosisScope, .localNetwork)
    }

    func testWeeklyDigestAggregatesSevenDayWindowAcrossHostsIncludingNoDataHosts() throws {
        let endingAt = Date(timeIntervalSince1970: 10_000)
        let first = HostConfig(id: UUID(), displayName: "First", address: "1.1.1.1")
        let second = HostConfig(id: UUID(), displayName: "Second", address: "8.8.8.8")
        let noData = HostConfig(id: UUID(), displayName: "No data", address: "9.9.9.9")
        let firstSamples = [
            success(first.id, at: endingAt.addingTimeInterval(-40), latency: 10, interface: "wifi"),
            failure(first.id, at: endingAt.addingTimeInterval(-30), interface: "wifi"),
            success(first.id, at: endingAt.addingTimeInterval(-20), latency: 30, interface: "wifi")
        ]
        let secondSamples = [
            success(second.id, at: endingAt.addingTimeInterval(-40), latency: 50, interface: "cellular"),
            failure(second.id, at: endingAt.addingTimeInterval(-20), interface: "cellular")
        ]

        let digest = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [first, second, noData],
            samplesByHost: [first.id: firstSamples, second.id: secondSamples],
            endingAt: endingAt
        ))

        XCTAssertEqual(digest.monitoredHostCount, 3)
        XCTAssertEqual(digest.hostsWithDataCount, 2)
        XCTAssertEqual(digest.sampleCount, 5)
        XCTAssertEqual(digest.uptimePercent, 60, accuracy: 0.001)
        XCTAssertEqual(digest.incidentCount, 2)
        XCTAssertEqual(digest.totalDowntime, 30, accuracy: 0.001)
        XCTAssertEqual(digest.worstHostID, second.id)
        XCTAssertEqual(digest.worstHostName, "Second")
        XCTAssertEqual(digest.averageMilliseconds, 30)
        XCTAssertEqual(digest.p95Milliseconds, 50)
        XCTAssertEqual(digest.busiestInterface, "wifi")
        XCTAssertEqual(digest.busiestInterfaceLabel, "Wi-Fi")
    }

    func testWeeklyDigestExcludesSamplesOutsideWindowAndIsStructurallyAbsentWithoutHistory() {
        let endingAt = Date(timeIntervalSince1970: 1_000_000)
        let host = HostConfig(id: UUID(), displayName: "Host", address: "example.com")
        let old = success(host.id, at: endingAt.addingTimeInterval(-(7 * 86_400) - 1), latency: 999)

        XCTAssertNil(HistoryWeeklyDigest.make(hosts: [host], samplesByHost: [:], endingAt: endingAt))
        XCTAssertNil(HistoryWeeklyDigest.make(hosts: [host], samplesByHost: [host.id: [old]], endingAt: endingAt))
    }

    func testWeeklyDigestIncludesSampleExactlyAtLowerBoundary() throws {
        let endingAt = Date(timeIntervalSince1970: 2_000_000)
        let host = HostConfig(id: UUID(), displayName: "Boundary", address: "example.com")
        let boundary = success(
            host.id,
            at: endingAt.addingTimeInterval(-HistoryWeeklyDigest.windowDuration),
            latency: 12
        )

        let digest = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [host], samplesByHost: [host.id: [boundary]], endingAt: endingAt
        ))

        XCTAssertEqual(digest.sampleCount, 1)
    }

    func testIncidentLogAllFailingSamplesRemainOngoing() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 3_000_000)
        let samples = (0..<4).map { failure(hostID, at: start.addingTimeInterval(Double($0) * 10)) }

        let incident = try XCTUnwrap(HistoryIncidentLog(samples: samples, endingAt: start.addingTimeInterval(60)).incidents.single)

        XCTAssertNil(incident.endDate)
        XCTAssertEqual(incident.sampleCount, samples.count)
    }

    private func success(
        _ hostID: UUID,
        at date: Date,
        latency: Double,
        interface: String? = nil
    ) -> PingResult {
        .success(hostID: hostID, latency: .milliseconds(latency), timestamp: date, networkInterface: interface)
    }

    private func failure(_ hostID: UUID, at date: Date, interface: String? = nil) -> PingResult {
        .failure(hostID: hostID, reason: .timeout, timestamp: date, networkInterface: interface)
    }
}

private extension Collection where Element == HistoryIncident {
    var single: Element? { count == 1 ? first : nil }
}
