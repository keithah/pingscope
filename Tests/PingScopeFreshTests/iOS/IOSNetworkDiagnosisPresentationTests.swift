import PingScopeCore
import PingScopeHistoryKit
import PingScopeiOS
import XCTest

final class IOSNetworkDiagnosisPresentationTests: XCTestCase {
    func testMonitorInsightsVisibilityHidesDiagnosisButKeepsStarlinkWhenConnectivityTipsAreOff() {
        let presentation = makeMonitorInsightsWithDiagnosisAndStarlink()

        let visibility = PingScopeIOSMonitorInsightsVisibility(
            presentation: presentation,
            connectivityTipsEnabled: false
        )

        XCTAssertNil(visibility.diagnosis)
        XCTAssertEqual(visibility.starlink, presentation.starlink)
        XCTAssertTrue(visibility.hasContent)
    }

    func testMonitorInsightsVisibilityShowsDiagnosisWhenConnectivityTipsAreOn() {
        let presentation = makeMonitorInsightsWithDiagnosisAndStarlink()

        let visibility = PingScopeIOSMonitorInsightsVisibility(
            presentation: presentation,
            connectivityTipsEnabled: true
        )

        XCTAssertEqual(visibility.diagnosis, presentation.diagnosis)
        XCTAssertEqual(visibility.starlink, presentation.starlink)
    }

    func testSharedDiagnosisPresentationDefinesMacAndIOSSemanticsForEveryScope() {
        let cases: [(NetworkPerspectiveDiagnosis, String, NetworkDiagnosisPresentation.Tone, Bool)] = [
            (
                NetworkPerspectiveDiagnosis(
                    scope: .localNetwork,
                    title: "Local network down",
                    detail: "Gateway is not responding.",
                    verdict: .localNetworkDown
                ),
                "network.slash",
                .red,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .upstream,
                    title: "ISP path down",
                    detail: "The router responds.",
                    verdict: .ispPathDown
                ),
                "wifi.exclamationmark",
                .orange,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .upstream,
                    title: "Upstream path down",
                    detail: "Internet checks are unreachable.",
                    verdict: .upstreamDown
                ),
                "wifi.exclamationmark",
                .orange,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .remoteService,
                    title: "Remote host down",
                    detail: "Inner tiers remain reachable.",
                    verdict: .remoteServiceDown(hostIDs: [UUID()])
                ),
                "exclamationmark.triangle.fill",
                .yellow,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .partialDegradation,
                    title: "Internet check degraded",
                    detail: "Latency is above threshold.",
                    verdict: .partialDegradation(tier: .upstream)
                ),
                "speedometer",
                .yellow,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .partialDegradation,
                    title: "Multiple failures",
                    detail: "Several checks failed.",
                    verdict: .multipleFailures(hostIDs: [UUID(), UUID()])
                ),
                "speedometer",
                .yellow,
                true
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .allReachable,
                    title: "Everything reachable",
                    detail: "All monitored hosts are responding.",
                    verdict: .allReachable
                ),
                "checkmark.circle.fill",
                .green,
                false
            ),
            (
                NetworkPerspectiveDiagnosis(
                    scope: .noData,
                    title: "Not enough data",
                    detail: "Waiting for samples.",
                    verdict: .noData
                ),
                "circle",
                .gray,
                false
            ),
        ]

        for (diagnosis, expectedSymbol, expectedTone, expectedShowsCompactRow) in cases {
            let shared = NetworkDiagnosisPresentation(diagnosis: diagnosis)
            let ios = PingScopeIOSDiagnosisPresentation(diagnosis: diagnosis)

            XCTAssertEqual(shared.label, diagnosis.title)
            XCTAssertEqual(shared.detail, diagnosis.detail)
            XCTAssertEqual(shared.systemImage, expectedSymbol)
            XCTAssertEqual(shared.tone, expectedTone)
            XCTAssertEqual(shared.showsCompactRow, expectedShowsCompactRow)
            XCTAssertEqual(ios.label, shared.label)
            XCTAssertEqual(ios.detail, shared.detail)
            XCTAssertEqual(ios.systemImage, shared.systemImage)
            XCTAssertEqual(ios.tone.rawValue, shared.tone.rawValue)
            XCTAssertEqual(ios.accessibilityLabel, shared.accessibilityLabel)
            XCTAssertEqual(ios.showsCompactRow, shared.showsCompactRow)
        }
    }

    func testDiagnosisPresentationIncludesEvidenceAndTentativeConfidenceInAccessibilityText() {
        let diagnosis = NetworkPerspectiveDiagnosis(
            scope: .upstream,
            title: "Upstream path down",
            detail: "Internet checks are unreachable.",
            verdict: .upstreamDown,
            confidence: .tentative,
            evidenceNote: "1/2 upstream hosts down"
        )

        let presentation = PingScopeIOSDiagnosisPresentation(diagnosis: diagnosis)

        XCTAssertEqual(
            presentation.detail,
            "Internet checks are unreachable. 1/2 upstream hosts down."
        )
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Upstream path down. Internet checks are unreachable. 1/2 upstream hosts down. Tentative"
        )
    }

    func testSharedStarlinkPresentationDefinesMacAndIOSFormatting() throws {
        let host = HostConfig.defaultStarlinkDish
        let telemetry = StarlinkTelemetry(
            state: "CONNECTED",
            popPingDropRate: 0.126,
            downlinkThroughputBps: 82_600_000,
            uplinkThroughputBps: 12_400_000,
            fractionObstructed: 0.034,
            uptimeSeconds: 183_600,
            activeAlerts: ["THERMAL_THROTTLE", "MOTORS_STUCK"]
        )

        let shared = try XCTUnwrap(
            StarlinkTelemetryPresentation(host: host, telemetry: telemetry)
        )
        let ios = try XCTUnwrap(
            PingScopeIOSStarlinkPresentation(host: host, telemetry: telemetry)
        )

        XCTAssertEqual(shared.state, "CONNECTED")
        XCTAssertEqual(shared.dropRate, "13%")
        XCTAssertEqual(shared.obstruction, "3%")
        XCTAssertEqual(shared.downlinkThroughput, "83 Mbps")
        XCTAssertEqual(shared.uplinkThroughput, "12 Mbps")
        XCTAssertEqual(shared.uptime, "2d 3h")
        XCTAssertEqual(shared.alerts, "THERMAL_THROTTLE, MOTORS_STUCK")
        XCTAssertEqual(ios.hostID, host.id)
        XCTAssertEqual(ios.hostName, host.displayName)
        XCTAssertEqual(ios.state, shared.state)
        XCTAssertEqual(ios.dropRate, shared.dropRate)
        XCTAssertEqual(ios.obstruction, shared.obstruction)
        XCTAssertEqual(ios.downlinkThroughput, shared.downlinkThroughput)
        XCTAssertEqual(ios.uplinkThroughput, shared.uplinkThroughput)
        XCTAssertEqual(ios.uptime, shared.uptime)
        XCTAssertEqual(ios.alerts, shared.alerts)
    }

    func testStarlinkPresentationUsesPlaceholdersForMissingFieldsInAvailableTelemetry() throws {
        let telemetry = StarlinkTelemetry(state: "CONNECTED")
        let shared = StarlinkTelemetryPresentation(telemetry: telemetry)
        let presentation = try XCTUnwrap(
            PingScopeIOSStarlinkPresentation(
                host: .defaultStarlinkDish,
                telemetry: telemetry
            )
        )

        XCTAssertEqual(presentation.state, shared.state)
        XCTAssertEqual(presentation.state, "CONNECTED")
        XCTAssertEqual(shared.dropRate, "--")
        XCTAssertEqual(shared.obstruction, "--")
        XCTAssertEqual(shared.downlinkThroughput, "--")
        XCTAssertEqual(shared.uplinkThroughput, "--")
        XCTAssertEqual(shared.uptime, "--")
        XCTAssertNil(shared.alerts)
        XCTAssertEqual(presentation.dropRate, shared.dropRate)
        XCTAssertEqual(presentation.obstruction, shared.obstruction)
        XCTAssertEqual(presentation.downlinkThroughput, shared.downlinkThroughput)
        XCTAssertEqual(presentation.uplinkThroughput, shared.uplinkThroughput)
        XCTAssertEqual(presentation.uptime, shared.uptime)
        XCTAssertEqual(presentation.alerts, shared.alerts)
    }

    func testStarlinkPresentationIsStructurallyAbsentWithoutCapabilityOrTelemetry() {
        let normalHost = HostConfig.defaultInternet

        XCTAssertNil(PingScopeIOSStarlinkPresentation(host: normalHost, telemetry: nil))
        XCTAssertNil(
            PingScopeIOSStarlinkPresentation(
                host: normalHost,
                telemetry: StarlinkTelemetry(state: "CONNECTED")
            )
        )
        XCTAssertNil(PingScopeIOSStarlinkPresentation(host: .defaultStarlinkDish, telemetry: nil))
        XCTAssertNil(
            PingScopeIOSStarlinkPresentation(
                host: .defaultStarlinkDish,
                telemetry: StarlinkTelemetry()
            )
        )
    }

    func testLatestStarlinkPresentationUsesNewestTelemetryFromLiveSamples() throws {
        let host = HostConfig.defaultStarlinkDish
        let first = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(40),
            timestamp: Date(timeIntervalSince1970: 100),
            metadata: ProbeMetadata(starlink: StarlinkTelemetry(state: "SEARCHING"))
        )
        let latest = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(30),
            timestamp: Date(timeIntervalSince1970: 200),
            metadata: ProbeMetadata(starlink: StarlinkTelemetry(state: "CONNECTED"))
        )

        let middle = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(35),
            timestamp: Date(timeIntervalSince1970: 150),
            metadata: ProbeMetadata(starlink: StarlinkTelemetry(state: "BOOTING"))
        )

        let presentation = try XCTUnwrap(
            PingScopeIOSStarlinkPresentation.latest(host: host, samples: [latest, first, middle])
        )

        XCTAssertEqual(presentation.state, "CONNECTED")
    }

    func testMonitorInsightsReuseCoreDiagnosisAcrossAllHostsAndExposeStarlinkTelemetry() throws {
        let gateway = HostConfig.defaultGateway
        let starlink = HostConfig.defaultStarlinkDish
        let date = Date(timeIntervalSince1970: 300)
        let gatewayResult = PingResult.success(
            hostID: gateway.id,
            latency: .milliseconds(4),
            timestamp: date
        )
        let starlinkResult = PingResult.failure(
            hostID: starlink.id,
            reason: .timeout,
            timestamp: date,
            metadata: ProbeMetadata(starlink: StarlinkTelemetry(state: "SEARCHING"))
        )
        var gatewayHealth = HostHealth(hostID: gateway.id, thresholds: gateway.thresholds)
        gatewayHealth.ingest(gatewayResult)
        var starlinkHealth = HostHealth(hostID: starlink.id, thresholds: starlink.thresholds)
        for _ in 0..<starlink.thresholds.downAfterFailures {
            starlinkHealth.ingest(starlinkResult)
        }
        var gatewaySeries = SampleSeries(hostID: gateway.id)
        gatewaySeries.append(gatewayResult)
        var starlinkSeries = SampleSeries(hostID: starlink.id)
        starlinkSeries.append(starlinkResult)

        let presentation = PingScopeIOSMonitorInsightsPresentation(snapshots: [
            LiveMonitorSessionSnapshot(
                host: gateway,
                session: nil,
                health: gatewayHealth,
                series: gatewaySeries
            ),
            LiveMonitorSessionSnapshot(
                host: starlink,
                session: nil,
                health: starlinkHealth,
                series: starlinkSeries
            ),
        ])

        XCTAssertEqual(presentation.diagnosis?.label, "Local network down")
        XCTAssertEqual(presentation.diagnosis?.tone, .red)
        XCTAssertEqual(presentation.starlink.count, 1)
        XCTAssertEqual(presentation.starlink.first?.hostID, starlink.id)
        XCTAssertEqual(presentation.starlink.first?.state, "SEARCHING")
    }

    func testMonitorInsightsStructurallyOmitNonActionableDiagnosisAndUnavailableStarlink() {
        let host = HostConfig.defaultInternet
        let result = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(20),
            timestamp: Date(timeIntervalSince1970: 400)
        )
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(result)
        var series = SampleSeries(hostID: host.id)
        series.append(result)

        let presentation = PingScopeIOSMonitorInsightsPresentation(snapshots: [
            LiveMonitorSessionSnapshot(host: host, session: nil, health: health, series: series),
        ])

        XCTAssertNil(presentation.diagnosis)
        XCTAssertTrue(presentation.starlink.isEmpty)
        XCTAssertFalse(presentation.hasContent)
    }

    func testGatewayDegradationIsSuppressedOnCellularButPresentedOnWiFi() {
        let gateway = HostConfig.defaultGateway

        func presentation(interface: String) -> PingScopeIOSMonitorInsightsPresentation {
            let result = PingResult.success(
                hostID: gateway.id,
                latency: .milliseconds(gateway.thresholds.degradedMilliseconds + 1),
                timestamp: Date(timeIntervalSince1970: 500),
                networkInterface: interface
            )
            var health = HostHealth(hostID: gateway.id, thresholds: gateway.thresholds)
            health.ingest(result)
            var series = SampleSeries(hostID: gateway.id)
            series.append(result)
            return PingScopeIOSMonitorInsightsPresentation(snapshots: [
                LiveMonitorSessionSnapshot(
                    host: gateway,
                    session: nil,
                    health: health,
                    series: series
                ),
            ])
        }

        XCTAssertNil(presentation(interface: "cellular").diagnosis)
        XCTAssertEqual(presentation(interface: "wifi").diagnosis?.label, "Router / gateway degraded")
    }

    func testCellularSuppressesNonGatewayPrivateHostButKeepsDownUpstreamHost() {
        let privateISPEdge = HostConfig(
            id: UUID(),
            displayName: "Modem",
            address: "192.168.100.1",
            tier: .ispEdge
        )
        let upstream = HostConfig(
            id: UUID(),
            displayName: "Public DNS",
            address: "1.1.1.1",
            tier: .upstream
        )

        func downSnapshot(_ host: HostConfig) -> LiveMonitorSessionSnapshot {
            let result = PingResult.failure(
                hostID: host.id,
                reason: .timeout,
                timestamp: Date(timeIntervalSince1970: 600),
                networkInterface: "cellular"
            )
            var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
            for _ in 0..<host.thresholds.downAfterFailures { health.ingest(result) }
            var series = SampleSeries(hostID: host.id)
            series.append(result)
            return LiveMonitorSessionSnapshot(host: host, session: nil, health: health, series: series)
        }

        XCTAssertTrue(privateISPEdge.requiresLocalNetworkPermission)
        XCTAssertNil(PingScopeIOSMonitorInsightsPresentation(snapshots: [downSnapshot(privateISPEdge)]).diagnosis)
        XCTAssertEqual(
            PingScopeIOSMonitorInsightsPresentation(snapshots: [downSnapshot(upstream)]).diagnosis?.label,
            "Upstream path down"
        )
    }

    func testAllNilInterfacesFailOpenAndKeepGatewayDiagnosis() {
        let gateway = HostConfig.defaultGateway
        let result = PingResult.failure(hostID: gateway.id, reason: .timeout)
        var health = HostHealth(hostID: gateway.id, thresholds: gateway.thresholds)
        for _ in 0..<gateway.thresholds.downAfterFailures { health.ingest(result) }

        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [gateway],
            healthByHost: [gateway.id: health]
        )

        XCTAssertEqual(diagnosis.scope, .localNetwork)
    }

    func testMixedWiFiAndCellularLatestWindowDoesNotMisclassifyAsCellular() {
        let gateway = HostConfig.defaultGateway
        let local = HostConfig(
            id: UUID(),
            displayName: "LAN probe",
            address: "192.168.1.2",
            tier: .ispEdge
        )

        func downHealth(_ host: HostConfig, interface: String, timestamp: TimeInterval) -> HostHealth {
            let result = PingResult.failure(
                hostID: host.id,
                reason: .timeout,
                timestamp: Date(timeIntervalSince1970: timestamp),
                networkInterface: interface
            )
            var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
            for _ in 0..<host.thresholds.downAfterFailures { health.ingest(result) }
            return health
        }

        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [gateway, local],
            healthByHost: [
                gateway.id: downHealth(gateway, interface: "wifi", timestamp: 700),
                local.id: downHealth(local, interface: "cellular", timestamp: 701),
            ]
        )

        XCTAssertEqual(diagnosis.scope, .localNetwork)
        XCTAssertEqual(diagnosis.confidence, .tentative)
    }

    func testGatewayOnlyCellularDiagnosisIsNeutralRatherThanAllReachable() {
        let gateway = HostConfig.defaultGateway
        let result = PingResult.failure(
            hostID: gateway.id,
            reason: .timeout,
            networkInterface: "cellular"
        )
        var health = HostHealth(hostID: gateway.id, thresholds: gateway.thresholds)
        for _ in 0..<gateway.thresholds.downAfterFailures { health.ingest(result) }

        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [gateway],
            healthByHost: [gateway.id: health]
        )

        XCTAssertEqual(diagnosis.scope, .noData)
        XCTAssertEqual(diagnosis.verdict, .noData)
        XCTAssertEqual(diagnosis.title, "No cellular-path checks configured")
        XCTAssertEqual(diagnosis.affectedHostIDs, [])
    }

    private func makeMonitorInsightsWithDiagnosisAndStarlink() -> PingScopeIOSMonitorInsightsPresentation {
        let host = HostConfig.defaultStarlinkDish
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(30),
            metadata: ProbeMetadata(starlink: StarlinkTelemetry(state: "CONNECTED"))
        )
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(sample)
        var series = SampleSeries(hostID: host.id)
        series.append(sample)

        return PingScopeIOSMonitorInsightsPresentation(
            snapshots: [LiveMonitorSessionSnapshot(host: host, session: nil, health: health, series: series)],
            diagnose: { _, _, _, _ in
                NetworkPerspectiveDiagnosis(
                    scope: .upstream,
                    title: "Upstream path down",
                    detail: "Internet checks are unreachable.",
                    verdict: .upstreamDown
                )
            }
        )
    }
}
