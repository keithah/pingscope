import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeLiveActivityTests: XCTestCase {
    func testFocusedContentStateRoundTripsWithDefaultedPayloadFields() throws {
        let state = makeContentState()

        let decoded = try roundTrip(state)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.mode, .focused)
        XCTAssertEqual(decoded.hostRows, [])
    }

    func testAllHostsContentStateRoundTrips() throws {
        let rows = (0..<3).map { makePayloadRow(index: $0, sampleCount: 12) }
        let state = makeContentState(mode: .allHosts, hostRows: rows)

        XCTAssertEqual(try roundTrip(state), state)
    }

    func testContentStateCapsActivityPayloadRowsAndSamples() {
        let rows = (0..<4).map { makePayloadRow(index: $0, sampleCount: 20) }

        let state = makeContentState(mode: .allHosts, hostRows: rows)

        XCTAssertEqual(state.hostRows.count, 3)
        XCTAssertEqual(state.hostRows.map(\.samples.count), [12, 12, 12])
        XCTAssertEqual(state.hostRows.map(\.displayName), ["Host 0", "Host 1", "Host 2"])
    }

    func testOldScalarOnlyPayloadDecodesWithFocusedModeAndNoRows() throws {
        let oldScalarOnlyJSON = Data("""
        {
          "latencyMilliseconds":42,
          "status":"healthy",
          "lastUpdatedAt":0,
          "remainingSeconds":30,
          "isStale":false,
          "failureMessage":"Timed out"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.ContentState.self,
            from: oldScalarOnlyJSON
        )

        XCTAssertEqual(decoded.latencyMilliseconds, 42)
        XCTAssertEqual(decoded.status, .healthy)
        XCTAssertEqual(decoded.lastUpdatedAt, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(decoded.remainingSeconds, 30)
        XCTAssertFalse(decoded.isStale)
        XCTAssertEqual(decoded.failureMessage, "Timed out")
        XCTAssertEqual(decoded.mode, .focused)
        XCTAssertEqual(decoded.hostRows, [])
    }

    func testWorstCaseActivityPayloadIsUnderFourKilobytes() throws {
        let rows = (0..<3).map { index in
            PingScopeLiveActivityHostRow(
                hostID: UUID(),
                displayName: String(repeating: "H", count: 64),
                endpointCaption: String(repeating: "E", count: 96),
                status: .degraded,
                latestLatencyMilliseconds: Int.max,
                samples: Array(repeating: Int.max, count: 12),
                isStale: true
            )
        }
        let state = makeContentState(mode: .allHosts, hostRows: rows)

        let encoded = try JSONEncoder().encode(state)

        XCTAssertLessThan(encoded.count, 4_096)
    }

    private func makeContentState(
        mode: PingScopeLiveActivityMode = .focused,
        hostRows: [PingScopeLiveActivityHostRow] = []
    ) -> PingScopeLiveActivityAttributes.ContentState {
        PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 42,
            status: .healthy,
            lastUpdatedAt: Date(timeIntervalSinceReferenceDate: 123),
            remainingSeconds: 30,
            isStale: false,
            failureMessage: nil,
            mode: mode,
            hostRows: hostRows
        )
    }

    private func makePayloadRow(index: Int, sampleCount: Int) -> PingScopeLiveActivityHostRow {
        let host = HostConfig(
            id: UUID(),
            displayName: "Host \(index)",
            address: "host-\(index).example",
            method: .tcp
        )
        let samples = (0..<sampleCount).map { sample in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(sample)),
                timestamp: Date(timeIntervalSinceReferenceDate: Double(sample))
            )
        }
        let snapshot = PingScopeIOSHostRowSnapshot(
            host: host,
            health: nil,
            samples: samples,
            sampleLimit: sampleCount
        )

        return PingScopeLiveActivityHostRow(snapshot: snapshot)
    }

    private func roundTrip(
        _ state: PingScopeLiveActivityAttributes.ContentState
    ) throws -> PingScopeLiveActivityAttributes.ContentState {
        try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
    }
}
