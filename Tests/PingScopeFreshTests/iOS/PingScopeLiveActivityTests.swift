import CoreGraphics
import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeLiveActivityTests: XCTestCase {
    func testSupportOwnedWireEnumsPreserveCoreRawValuesAndCodableFieldNames() throws {
        let coreHealthStatuses: [HealthStatus] = [.noData, .healthy, .degraded, .down]
        XCTAssertEqual(PingScopeLiveActivityHealthStatus.allCases.map(\.rawValue), coreHealthStatuses.map(\.rawValue))
        XCTAssertEqual(PingScopeLiveActivityMethod.allCases.map(\.rawValue), PingMethod.allCases.map(\.rawValue))
        XCTAssertEqual(PingScopeLiveActivityDuration.allCases.map(\.rawValue), MonitorSessionDuration.allCases.map(\.rawValue))

        let attributes = PingScopeLiveActivityAttributes(
            hostID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            hostName: "Example",
            address: "example.com",
            method: .https,
            duration: .oneMinute
        )
        let state = PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 42,
            status: .degraded,
            lastUpdatedAt: nil,
            remainingSeconds: 30,
            isStale: false
        )
        let attributesJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any])
        let stateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])

        XCTAssertEqual(attributesJSON["method"] as? String, "https")
        XCTAssertEqual(attributesJSON["duration"] as? String, "oneMinute")
        XCTAssertEqual(stateJSON["status"] as? String, "degraded")
        XCTAssertEqual(Set(attributesJSON.keys), ["hostID", "hostName", "address", "method", "duration", "identityColor"])
        XCTAssertEqual(
            Set(stateJSON.keys),
            ["latencyMilliseconds", "status", "remainingSeconds", "isStale", "mode", "hostRows", "showsDynamicIslandDetails"]
        )
    }

    func testCoreAdaptersMapEveryLiveActivityWireEnumCase() {
        for value in [HealthStatus.noData, .healthy, .degraded, .down] {
            XCTAssertEqual(PingScopeLiveActivityHealthStatus(value).coreValue, value)
        }
        for value in PingMethod.allCases {
            XCTAssertEqual(PingScopeLiveActivityMethod(value).coreValue, value)
        }
        for value in MonitorSessionDuration.allCases {
            XCTAssertEqual(PingScopeLiveActivityDuration(value).coreValue, value)
        }

        let host = HostConfig(displayName: "Adapter", address: "adapter.example", method: .starlink)
        let attributes = PingScopeLiveActivityAttributes(host: host, duration: .thirtySeconds)
        XCTAssertEqual(attributes.method, .starlink)
        XCTAssertEqual(attributes.duration, .thirtySeconds)

        let row = PingScopeLiveActivityHostRow(
            hostID: host.id,
            displayName: host.displayName,
            endpointCaption: "Starlink adapter.example",
            status: HealthStatus.down,
            latestLatencyMilliseconds: nil,
            samples: [],
            isStale: false
        )
        XCTAssertEqual(row.status, .down)
    }

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

    func testDynamicIslandDetailPreferenceChoosesRichOrStatusOnlyWhileLockScreenRowsStayEqual() {
        let host = HostConfig(displayName: "Focused", address: "focused.example")
        let attributes = PingScopeLiveActivityAttributes(host: host, duration: .continuous)
        let rich = makeContentState(showsDynamicIslandDetails: true)
        let statusOnly = makeContentState(showsDynamicIslandDetails: false)

        let richRegions = PingScopeLiveActivityPresentation.dynamicIslandRegionDecisions(contentState: rich)
        XCTAssertEqual(richRegions.expanded, .rich)
        XCTAssertEqual(richRegions.compactLeading, .rich)
        XCTAssertEqual(richRegions.compactTrailing, .rich)
        XCTAssertEqual(richRegions.minimal, .rich)

        let statusOnlyRegions = PingScopeLiveActivityPresentation.dynamicIslandRegionDecisions(contentState: statusOnly)
        XCTAssertEqual(statusOnlyRegions.expanded, .statusOnly)
        XCTAssertEqual(statusOnlyRegions.compactLeading, .statusOnly)
        XCTAssertEqual(statusOnlyRegions.compactTrailing, .statusOnly)
        XCTAssertEqual(statusOnlyRegions.minimal, .statusOnly)
        XCTAssertEqual(
            PingScopeLiveActivityPresentation.rows(attributes: attributes, contentState: rich),
            PingScopeLiveActivityPresentation.rows(attributes: attributes, contentState: statusOnly)
        )
    }

    func testLegacyContentStateDefaultsDynamicIslandDetailsOn() throws {
        let legacy = Data("""
        {
          "latencyMilliseconds":42,
          "status":"healthy",
          "remainingSeconds":30,
          "isStale":false,
          "mode":"focused",
          "hostRows":[]
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.ContentState.self,
            from: legacy
        )

        XCTAssertTrue(decoded.showsDynamicIslandDetails)
    }

    func testLiveActivityIdentityColorMatchesResolvedCustomAndAutomaticColors() {
        let custom = HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        let customHost = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Custom",
            address: "custom.example",
            displayColor: custom
        )
        let automaticHost = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            displayName: "Automatic",
            address: "automatic.example"
        )

        for host in [customHost, automaticHost] {
            let expected = ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
            let attributes = PingScopeLiveActivityAttributes(host: host, duration: .continuous)
            let snapshot = PingScopeIOSHostRowSnapshot(host: host, health: nil)
            let row = PingScopeLiveActivityHostRow(snapshot: snapshot)

            assertIdentityColor(attributes.identityColor, equals: expected)
            assertIdentityColor(row.identityColor, equals: expected)
        }
    }

    func testFocusedPresentationUsesCurrentStateIdentityColorAfterHostEdit() {
        let host = HostConfig(displayName: "Focused", address: "focused.example")
        let updatedColor = WidgetGraphDisplayColor(
            light: WidgetGraphRGB(red: 0.2, green: 0.4, blue: 0.8),
            dark: WidgetGraphRGB(red: 0.2, green: 0.4, blue: 0.8)
        )
        let state = makeContentState(hostRows: [
            PingScopeLiveActivityHostRow(
                hostID: host.id,
                displayName: host.displayName,
                endpointCaption: "TCP focused.example",
                status: .healthy,
                latestLatencyMilliseconds: 42,
                samples: [42],
                isStale: false,
                identityColor: updatedColor
            )
        ])

        let presentation = PingScopeLiveActivityPresentation.rows(
            attributes: PingScopeLiveActivityAttributes(host: host, duration: .continuous),
            contentState: state
        )

        XCTAssertEqual(presentation.first?.identityColor, updatedColor)
    }

    func testMissingOrInvalidIdentityColorFallsBackToAutomatic() throws {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let missing = Data("""
        {
          "hostID":"\(hostID.uuidString)",
          "hostName":"Legacy",
          "address":"legacy.example",
          "method":"tcp",
          "duration":"continuous"
        }
        """.utf8)
        let invalid = Data("""
        {
          "hostID":"\(hostID.uuidString)",
          "hostName":"Invalid",
          "address":"invalid.example",
          "method":"tcp",
          "duration":"continuous",
          "identityColor":{
            "light":{"red":2,"green":0,"blue":0},
            "dark":{"red":0,"green":0,"blue":0}
          }
        }
        """.utf8)
        let expected = ResolvedHostDisplayColor(hostID: hostID, displayColor: nil)

        assertIdentityColor(
            try JSONDecoder().decode(PingScopeLiveActivityAttributes.self, from: missing).identityColor,
            equals: expected
        )
        assertIdentityColor(
            try JSONDecoder().decode(PingScopeLiveActivityAttributes.self, from: invalid).identityColor,
            equals: expected
        )
    }

    func testHostileFocusedAttributesInitializationKeepsCombinedPayloadUnderFourKilobytes() throws {
        let hostID = UUID()
        let attributes = PingScopeLiveActivityAttributes(
            host: HostConfig(
                id: hostID,
                displayName: String(repeating: "👩🏽‍💻", count: 200),
                address: oversizedAddress,
                method: .https,
                displayColor: worstCaseHostDisplayColor
            ),
            duration: .oneMinute
        )
        let state = makeContentState(
            failureMessage: oversizedFailureMessage,
            mode: .focused,
            hostRows: [makeOversizedPayloadRow()]
        )

        assertAttributeStringLimits(attributes)
        XCTAssertEqual(attributes.hostID, hostID)
        XCTAssertEqual(attributes.hostName, String(repeating: "👩🏽‍💻", count: 4))
        XCTAssertEqual(attributes.address, boundedAddress)
        XCTAssertEqual(attributes.method, .https)
        XCTAssertEqual(attributes.duration, .oneMinute)
        let payloadSize = try encodedCombinedPayloadSize(attributes: attributes, state: state)
        XCTAssertLessThan(payloadSize, 4_096)
    }

    func testHostileAllHostsPlaceholderInitializationKeepsCombinedPayloadUnderFourKilobytes() throws {
        let hostID = UUID()
        let attributes = PingScopeLiveActivityAttributes(
            host: HostConfig(
                id: hostID,
                displayName: "All Hosts",
                address: oversizedAddress,
                method: .udp,
                displayColor: worstCaseHostDisplayColor
            ),
            duration: .thirtySeconds
        )
        let state = makeContentState(
            failureMessage: oversizedFailureMessage,
            mode: .allHosts,
            hostRows: Array(repeating: makeOversizedPayloadRow(), count: 3)
        )

        assertAttributeStringLimits(attributes)
        XCTAssertEqual(attributes.hostID, hostID)
        XCTAssertEqual(attributes.hostName, "All Hosts")
        XCTAssertEqual(attributes.address, boundedAddress)
        XCTAssertEqual(attributes.method, .udp)
        XCTAssertEqual(attributes.duration, .thirtySeconds)
        let payloadSize = try encodedCombinedPayloadSize(attributes: attributes, state: state)
        XCTAssertLessThan(payloadSize, 4_096)
    }

    func testHostileAttributesDecodeKeepsCombinedPayloadUnderFourKilobytes() throws {
        let hostID = UUID()
        let unboundedAttributes = UnboundedLiveActivityAttributes(
            hostID: hostID,
            hostName: String(repeating: "All Hosts 👩🏽‍💻", count: 200),
            address: oversizedAddress,
            method: .icmp,
            duration: .continuous
        )
        let attributes = try JSONDecoder().decode(
            PingScopeLiveActivityAttributes.self,
            from: JSONEncoder().encode(unboundedAttributes)
        )
        let state = makeContentState(
            failureMessage: oversizedFailureMessage,
            mode: .allHosts,
            hostRows: Array(repeating: makeOversizedPayloadRow(), count: 3)
        )

        assertAttributeStringLimits(attributes)
        XCTAssertEqual(attributes.hostID, hostID)
        XCTAssertEqual(attributes.address, boundedAddress)
        XCTAssertEqual(attributes.method, .icmp)
        XCTAssertEqual(attributes.duration, .continuous)
        XCTAssertLessThan(try encodedCombinedPayloadSize(attributes: attributes, state: state), 4_096)
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

    func testDynamicIslandExcludesGatewayWhileLockScreenKeepsAllRows() {
        let gatewaySnapshot = PingScopeIOSHostRowSnapshot(
            host: HostConfig.defaultGatewayHost(address: "192.168.1.1"),
            health: nil
        )
        XCTAssertTrue(gatewaySnapshot.isDefaultGateway)
        XCTAssertTrue(PingScopeLiveActivityHostRow(snapshot: gatewaySnapshot).isDefaultGateway)

        let dnsA = PingScopeLiveActivityHostRow(
            hostID: UUID(), displayName: "Cloudflare", endpointCaption: "HTTPS 1.1.1.1",
            status: .healthy, latestLatencyMilliseconds: 18, samples: [14, 18], isStale: false
        )
        let gateway = PingScopeLiveActivityHostRow(
            hostID: UUID(), displayName: "Default Gateway", endpointCaption: "UDP 192.168.1.1",
            status: .down, latestLatencyMilliseconds: nil, samples: [1, 2], isStale: false,
            isDefaultGateway: true
        )
        let dnsB = PingScopeLiveActivityHostRow(
            hostID: UUID(), displayName: "Google", endpointCaption: "TCP 8.8.8.8",
            status: .degraded, latestLatencyMilliseconds: 72, samples: [50, 72], isStale: false
        )
        let state = makeContentState(mode: .allHosts, hostRows: [dnsA, gateway, dnsB])
        let attributes = PingScopeLiveActivityAttributes(
            host: HostConfig(displayName: "All Hosts", address: "1.1.1.1"),
            duration: .continuous
        )

        let lockScreenRows = PingScopeLiveActivityPresentation.rows(
            attributes: attributes,
            contentState: state
        )
        let islandRows = PingScopeLiveActivityPresentation.dynamicIslandRows(
            attributes: attributes,
            contentState: state
        )

        XCTAssertEqual(lockScreenRows.map(\.displayName), ["Cloudflare", "Default Gateway", "Google"])
        XCTAssertEqual(islandRows.map(\.displayName), ["Cloudflare", "Google"])
        XCTAssertEqual(PingScopeLiveActivityPresentation.dynamicIslandAggregateStatus(contentState: state), .degraded)
    }

    func testLegacyHostRowPayloadDefaultsGatewayFlagToFalse() throws {
        let row = makePayloadRow(index: 0, sampleCount: 2)
        var encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        )
        encodedObject.removeValue(forKey: "isDefaultGateway")
        encodedObject.removeValue(forKey: "identityColor")

        let decoded = try JSONDecoder().decode(
            PingScopeLiveActivityHostRow.self,
            from: JSONSerialization.data(withJSONObject: encodedObject)
        )

        XCTAssertFalse(decoded.isDefaultGateway)
        assertIdentityColor(
            decoded.identityColor,
            equals: ResolvedHostDisplayColor(hostID: decoded.hostID, displayColor: nil)
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
            145
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
            124
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
            showsDynamicIslandDetails: false,
            at: startedAt.addingTimeInterval(6)
        )

        XCTAssertEqual(state.mode, .focused)
        XCTAssertEqual(state.latencyMilliseconds, 42)
        XCTAssertEqual(state.status, .healthy)
        XCTAssertFalse(state.showsDynamicIslandDetails)
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
        hostRows: [PingScopeLiveActivityHostRow] = [],
        showsDynamicIslandDetails: Bool = true
    ) -> PingScopeLiveActivityAttributes.ContentState {
        PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 42,
            status: .healthy,
            lastUpdatedAt: Date(timeIntervalSinceReferenceDate: 123),
            remainingSeconds: 30,
            isStale: false,
            failureMessage: failureMessage,
            mode: mode,
            hostRows: hostRows,
            showsDynamicIslandDetails: showsDynamicIslandDetails
        )
    }

    private func assertIdentityColor(
        _ actual: WidgetGraphDisplayColor,
        equals expected: ResolvedHostDisplayColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedLight = expected.components(for: .light)
        let expectedDark = expected.components(for: .dark)
        XCTAssertEqual(actual.light.red, expectedLight.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.light.green, expectedLight.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.light.blue, expectedLight.blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.dark.red, expectedDark.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.dark.green, expectedDark.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.dark.blue, expectedDark.blue, accuracy: 0.000_001, file: file, line: line)
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
            isStale: true,
            identityColor: WidgetGraphDisplayColor(
                light: WidgetGraphRGB(
                    red: 0.123_456_789_012_345_67,
                    green: 0.234_567_890_123_456_78,
                    blue: 0.345_678_901_234_567_9
                ),
                dark: WidgetGraphRGB(
                    red: 0.456_789_012_345_678_9,
                    green: 0.567_890_123_456_789,
                    blue: 0.678_901_234_567_890_1
                )
            )
        )
    }

    private var worstCaseHostDisplayColor: HostDisplayColor {
        HostDisplayColor(
            red: 0.123_456_789_012_345_67,
            green: 0.234_567_890_123_456_78,
            blue: 0.345_678_901_234_567_9
        )
    }

    private func assertAttributeStringLimits(_ attributes: PingScopeLiveActivityAttributes) {
        XCTAssertLessThanOrEqual(
            attributes.hostName.count,
            PingScopeLiveActivityAttributes.hostNameCharacterLimit
        )
        XCTAssertLessThanOrEqual(
            attributes.hostName.utf8.count,
            PingScopeLiveActivityAttributes.hostNameUTF8ByteLimit
        )
        XCTAssertLessThanOrEqual(
            attributes.address.count,
            PingScopeLiveActivityAttributes.addressCharacterLimit
        )
        XCTAssertLessThanOrEqual(
            attributes.address.utf8.count,
            PingScopeLiveActivityAttributes.addressUTF8ByteLimit
        )
    }

    private func encodedCombinedPayloadSize(
        attributes: PingScopeLiveActivityAttributes,
        state: PingScopeLiveActivityAttributes.ContentState
    ) throws -> Int {
        try JSONEncoder().encode(
            CombinedLiveActivityPayload(attributes: attributes, contentState: state)
        ).count
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

    private var oversizedAddress: String {
        String(repeating: "连接-", count: 500)
    }

    private var boundedAddress: String {
        String(repeating: "连接-", count: 42) + "连接"
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

private struct CombinedLiveActivityPayload: Encodable {
    let attributes: PingScopeLiveActivityAttributes
    let contentState: PingScopeLiveActivityAttributes.ContentState
}

private struct UnboundedLiveActivityAttributes: Encodable {
    let hostID: UUID
    let hostName: String
    let address: String
    let method: PingMethod
    let duration: MonitorSessionDuration
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
        status = row.status.coreValue
        latestLatencyMilliseconds = row.latestLatencyMilliseconds
        samples = Array(repeating: Int.max, count: 20)
        isStale = row.isStale
    }
}
