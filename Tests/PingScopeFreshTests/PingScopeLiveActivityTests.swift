import CoreGraphics
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

    func testFocusedPresentationUsesScalarIdentityAndLatencyWithBoundedSparkline() {
        let host = HostConfig(
            displayName: "Focused Host",
            address: "focused.example",
            method: .https
        )
        let state = makeContentState(
            mode: .focused,
            hostRows: [
                PingScopeLiveActivityHostRow(
                    hostID: host.id,
                    displayName: "Outdated row identity",
                    endpointCaption: "TCP ignored.example",
                    status: .down,
                    latestLatencyMilliseconds: nil,
                    samples: [18, 42],
                    isStale: true
                )
            ]
        )

        let rows = PingScopeLiveActivityPresentation.rows(
            attributes: PingScopeLiveActivityAttributes(host: host, duration: .continuous),
            contentState: state
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayName, "Focused Host")
        XCTAssertEqual(rows[0].endpointCaption, "HTTPS focused.example")
        XCTAssertEqual(rows[0].status, .healthy)
        XCTAssertEqual(rows[0].latencyText, "42ms")
        XCTAssertEqual(rows[0].samples, [18, 42])
    }

    func testAllHostsPresentationPreservesOrderAndHidesStaleOrUnavailableLatency() {
        let rows = [
            PingScopeLiveActivityHostRow(
                hostID: UUID(),
                displayName: "First",
                endpointCaption: "HTTPS first.example",
                status: .healthy,
                latestLatencyMilliseconds: 18,
                samples: [14, 18],
                isStale: false
            ),
            PingScopeLiveActivityHostRow(
                hostID: UUID(),
                displayName: "Second",
                endpointCaption: "TCP second.example",
                status: .degraded,
                latestLatencyMilliseconds: 89,
                samples: [42, 89],
                isStale: true
            ),
            PingScopeLiveActivityHostRow(
                hostID: UUID(),
                displayName: "Third",
                endpointCaption: "UDP third.example",
                status: .noData,
                latestLatencyMilliseconds: 12,
                samples: [12],
                isStale: false
            )
        ]
        let state = makeContentState(mode: .allHosts, hostRows: rows)
        let attributes = PingScopeLiveActivityAttributes(
            host: HostConfig(displayName: "Placeholder", address: "placeholder.example"),
            duration: .oneMinute
        )

        let presentation = PingScopeLiveActivityPresentation.rows(
            attributes: attributes,
            contentState: state
        )

        XCTAssertEqual(presentation.map(\.displayName), ["First", "Second", "Third"])
        XCTAssertEqual(presentation.map(\.latencyText), ["18ms", "--ms", "--ms"])
        XCTAssertEqual(presentation.map(\.samples), [[14, 18], [42, 89], [12]])
        XCTAssertEqual(presentation.map(\.status), [.healthy, .noData, .noData])
        XCTAssertEqual(
            presentation[1].accessibilityLabel,
            "Second, TCP second.example, Stale, Latency unavailable"
        )
    }

    func testSessionPresentationUsesOneLiveOrRemainingLabel() {
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.sessionText(duration: .continuous, remainingSeconds: 0),
            "Live"
        )
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.sessionText(
                duration: .continuous,
                remainingSeconds: 0,
                isStale: true
            ),
            "Stale"
        )
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.sessionText(duration: .oneMinute, remainingSeconds: 31),
            "31s"
        )
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.sessionText(duration: .thirtySeconds, remainingSeconds: 0),
            "Ended"
        )
    }

    func testAggregatePresentationUsesNeutralStatusWhenActivityIsStale() {
        let state = PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 42,
            status: .healthy,
            lastUpdatedAt: nil,
            remainingSeconds: 30,
            isStale: true
        )

        XCTAssertEqual(PingScopeLiveActivityPresentation.aggregateStatus(contentState: state), .noData)
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.aggregateStatusAccessibilityDescription(contentState: state),
            "Stale"
        )
    }

    func testRowPresentationAccessibilityDescribesUnavailableLatency() {
        let payloadRow = PingScopeLiveActivityHostRow(
            hostID: UUID(),
            displayName: "Offline Host",
            endpointCaption: "HTTPS offline.example",
            status: .down,
            latestLatencyMilliseconds: 93,
            samples: [21, 93],
            isStale: false
        )
        let row = PingScopeLiveActivityPresentation.rows(
            attributes: PingScopeLiveActivityAttributes(
                host: HostConfig(displayName: "Placeholder", address: "placeholder.example"),
                duration: .continuous
            ),
            contentState: makeContentState(mode: .allHosts, hostRows: [payloadRow])
        )[0]

        XCTAssertEqual(
            row.accessibilityLabel,
            "Offline Host, HTTPS offline.example, Down, Latency unavailable"
        )
    }

    func testSparklinePointsStayInsideTheirFixedBounds() {
        XCTAssertEqual(
            PingScopeLiveActivitySparklinePresentation.points(
                samples: [10, 20, 30],
                in: CGSize(width: 72, height: 28)
            ),
            [
                CGPoint(x: 1, y: 27),
                CGPoint(x: 36, y: 14),
                CGPoint(x: 71, y: 1)
            ]
        )
        XCTAssertTrue(
            PingScopeLiveActivitySparklinePresentation.points(
                samples: [42],
                in: CGSize(width: 72, height: 28)
            ).isEmpty
        )
    }

    func testLiveActivityLayoutCapsThreeRowLockScreenAndExpandedIslandHeights() {
        let hostRowLimit = PingScopeLiveActivityAttributes.ContentState.hostRowLimit

        XCTAssertEqual(
            PingScopeLiveActivityLayout.maximumLockScreenContentHeight,
            147
        )
        XCTAssertLessThanOrEqual(
            PingScopeLiveActivityLayout.maximumLockScreenContentHeight,
            PingScopeLiveActivityLayout.lockScreenActivityHeightLimit
        )
        XCTAssertEqual(
            PingScopeLiveActivityLayout.lockScreenContentHeight(forHostRows: hostRowLimit + 1),
            PingScopeLiveActivityLayout.maximumLockScreenContentHeight
        )

        XCTAssertEqual(
            PingScopeLiveActivityLayout.maximumExpandedIslandContentHeight,
            125
        )
        XCTAssertLessThanOrEqual(
            PingScopeLiveActivityLayout.maximumExpandedIslandContentHeight,
            PingScopeLiveActivityLayout.expandedIslandSafeHeightLimit
        )
    }

    func testFocusedContentStateBuilderIncludesBoundedCurrentHostRow() {
        let host = HostConfig(displayName: "Focused Host", address: "focused.example", method: .https)
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let latest = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(42),
            timestamp: startedAt.addingTimeInterval(5)
        )
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(latest)
        let samples = (0..<14).map { index in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(index)),
                timestamp: startedAt.addingTimeInterval(Double(index))
            )
        }
        let session = MonitorSessionState(
            hostID: host.id,
            duration: .oneMinute,
            startedAt: startedAt,
            latestResult: latest
        )

        let state = PingScopeIOSLiveActivityContentStateBuilder.focused(
            host: host,
            session: session,
            health: health,
            samples: samples,
            at: startedAt.addingTimeInterval(6)
        )

        XCTAssertEqual(state.mode, .focused)
        XCTAssertEqual(state.latencyMilliseconds, 42)
        XCTAssertEqual(state.status, .healthy)
        XCTAssertEqual(state.hostRows.count, 1)
        XCTAssertEqual(state.hostRows[0].hostID, host.id)
        XCTAssertEqual(state.hostRows[0].displayName, "Focused Host")
        XCTAssertEqual(state.hostRows[0].endpointCaption, "HTTPS focused.example")
        XCTAssertEqual(state.hostRows[0].latestLatencyMilliseconds, 42)
        XCTAssertFalse(state.hostRows[0].isStale)
        XCTAssertEqual(state.hostRows[0].samples.count, PingScopeLiveActivityHostRow.sampleLimit)
        XCTAssertEqual(state.hostRows[0].samples.first, 0)
        XCTAssertEqual(state.hostRows[0].samples.last, 13)
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

    func testOldScalarOnlyPayloadClampsHostileFailureMessage() throws {
        let oldScalarOnlyJSON = Data("""
        {
          "latencyMilliseconds":42,
          "status":"healthy",
          "lastUpdatedAt":0,
          "remainingSeconds":30,
          "isStale":false,
          "failureMessage":"\(oversizedFailureMessage)"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.ContentState.self,
            from: oldScalarOnlyJSON
        )

        try assertFailureMessageLimit(decoded)
        XCTAssertEqual(decoded.mode, .focused)
        XCTAssertEqual(decoded.hostRows, [])
        XCTAssertLessThan(try JSONEncoder().encode(decoded).count, 4_096)
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

    func testPayloadInitializationClampsUnicodeStringsAndCollections() throws {
        let row = makeOversizedPayloadRow()
        let state = makeContentState(
            failureMessage: oversizedFailureMessage,
            mode: .allHosts,
            hostRows: Array(repeating: row, count: 4)
        )

        XCTAssertEqual(state.hostRows.count, PingScopeLiveActivityAttributes.ContentState.hostRowLimit)
        XCTAssertEqual(state.hostRows.map(\.samples.count), Array(repeating: PingScopeLiveActivityHostRow.sampleLimit, count: 3))
        assertPayloadStringLimits(state.hostRows)
        try assertFailureMessageLimit(state)
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4_096)
    }

    func testPayloadDecodingClampsUnicodeStringsAndCollections() throws {
        let row = makeOversizedPayloadRow()
        let oversizedState = UnboundedContentState(
            latencyMilliseconds: 42,
            status: .healthy,
            lastUpdatedAt: Date(timeIntervalSinceReferenceDate: 123),
            remainingSeconds: 30,
            isStale: false,
            failureMessage: oversizedFailureMessage,
            mode: .allHosts,
            hostRows: Array(repeating: UnboundedHostRow(row), count: 4)
        )

        let decoded = try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(oversizedState)
        )

        XCTAssertEqual(decoded.hostRows.count, PingScopeLiveActivityAttributes.ContentState.hostRowLimit)
        XCTAssertEqual(decoded.hostRows.map(\.samples.count), Array(repeating: PingScopeLiveActivityHostRow.sampleLimit, count: 3))
        assertPayloadStringLimits(decoded.hostRows)
        try assertFailureMessageLimit(decoded)
        XCTAssertLessThan(try JSONEncoder().encode(decoded).count, 4_096)
    }

    private func makeContentState(
        failureMessage: String? = nil,
        mode: PingScopeLiveActivityMode = .focused,
        hostRows: [PingScopeLiveActivityHostRow] = []
    ) -> PingScopeLiveActivityAttributes.ContentState {
        PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 42,
            status: .healthy,
            lastUpdatedAt: Date(timeIntervalSinceReferenceDate: 123),
            remainingSeconds: 30,
            isStale: false,
            failureMessage: failureMessage,
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

    private func makeOversizedPayloadRow() -> PingScopeLiveActivityHostRow {
        PingScopeLiveActivityHostRow(
            hostID: UUID(),
            displayName: String(repeating: "👩🏽‍💻", count: 200),
            endpointCaption: String(repeating: "连接-", count: 200),
            status: .degraded,
            latestLatencyMilliseconds: Int.max,
            samples: Array(repeating: Int.max, count: 20),
            isStale: true
        )
    }

    private func assertPayloadStringLimits(_ rows: [PingScopeLiveActivityHostRow]) {
        for row in rows {
            XCTAssertEqual(row.displayName, String(repeating: "👩🏽‍💻", count: 4))
            XCTAssertEqual(row.endpointCaption, String(repeating: "连接-", count: 16))
            XCTAssertLessThanOrEqual(row.displayName.count, PingScopeLiveActivityHostRow.displayNameCharacterLimit)
            XCTAssertLessThanOrEqual(row.displayName.utf8.count, PingScopeLiveActivityHostRow.displayNameUTF8ByteLimit)
            XCTAssertLessThanOrEqual(row.endpointCaption.count, PingScopeLiveActivityHostRow.endpointCaptionCharacterLimit)
            XCTAssertLessThanOrEqual(row.endpointCaption.utf8.count, PingScopeLiveActivityHostRow.endpointCaptionUTF8ByteLimit)
        }
    }

    private func assertFailureMessageLimit(_ state: PingScopeLiveActivityAttributes.ContentState) throws {
        let failureMessage = try XCTUnwrap(state.failureMessage)
        XCTAssertEqual(failureMessage, String(repeating: "👩🏽‍💻", count: 12))
        XCTAssertLessThanOrEqual(failureMessage.count, PingScopeLiveActivityAttributes.ContentState.failureMessageCharacterLimit)
        XCTAssertLessThanOrEqual(failureMessage.utf8.count, PingScopeLiveActivityAttributes.ContentState.failureMessageUTF8ByteLimit)
    }

    private var oversizedFailureMessage: String {
        String(repeating: "👩🏽‍💻", count: 200)
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

private struct UnboundedContentState: Codable {
    let latencyMilliseconds: Int?
    let status: HealthStatus
    let lastUpdatedAt: Date?
    let remainingSeconds: Int
    let isStale: Bool
    let failureMessage: String?
    let mode: PingScopeLiveActivityMode
    let hostRows: [UnboundedHostRow]
}

private struct UnboundedHostRow: Codable {
    let hostID: UUID
    let displayName: String
    let endpointCaption: String
    let status: HealthStatus
    let latestLatencyMilliseconds: Int?
    let samples: [Int]
    let isStale: Bool

    init(_ row: PingScopeLiveActivityHostRow) {
        hostID = row.hostID
        displayName = String(repeating: "👩🏽‍💻", count: 200)
        endpointCaption = String(repeating: "连接-", count: 200)
        status = row.status
        latestLatencyMilliseconds = row.latestLatencyMilliseconds
        samples = Array(repeating: Int.max, count: 20)
        isStale = row.isStale
    }
}
