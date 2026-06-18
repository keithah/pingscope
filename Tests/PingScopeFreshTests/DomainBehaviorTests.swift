import XCTest
@testable import PingScopeCore

final class DomainBehaviorTests: XCTestCase {
    func testHostConfigValidationRequiresUsableNameAndAddress() {
        let invalid = HostConfig(displayName: "  ", address: "\n")
        let expectedErrors: [HostValidationError] = [.missingDisplayName, .missingAddress]
        XCTAssertEqual(invalid.validationErrors, expectedErrors)

        let valid = HostConfig(displayName: "Cloudflare", address: "1.1.1.1")
        XCTAssertTrue(valid.validationErrors.isEmpty)
    }

    func testHostConfigValidationRejectsInvalidTimingAndThresholds() {
        let invalid = HostConfig(
            displayName: "Example",
            address: "example.com",
            port: 0,
            interval: .milliseconds(100),
            timeout: .milliseconds(50),
            thresholds: LatencyThresholds(degradedMilliseconds: 0, downAfterFailures: 0)
        )

        XCTAssertEqual(invalid.validationErrors, [
            .invalidPort,
            .intervalTooShort,
            .timeoutTooShort,
            .degradedThresholdTooLow
        ])
    }

    func testHostConfigValidationRequiresPortsForConnectionBasedMethods() {
        let tcp = HostConfig(displayName: "Example", address: "example.com", method: .tcp, port: nil)
        let udp = HostConfig(displayName: "Example", address: "example.com", method: .udp, port: nil)
        let icmp = HostConfig(displayName: "Example", address: "example.com", method: .icmp, port: nil)

        XCTAssertEqual(tcp.validationErrors, [.invalidPort])
        XCTAssertEqual(udp.validationErrors, [.invalidPort])
        XCTAssertTrue(icmp.validationErrors.isEmpty)
    }

    func testHostConfigApplyingMethodSetsMethodAwarePort() {
        var host = HostConfig(displayName: "Example", address: "example.com", method: .tcp, port: 443)

        host.apply(method: .udp)
        XCTAssertEqual(host.method, .udp)
        XCTAssertEqual(host.port, 53)

        host.apply(method: .icmp)
        XCTAssertEqual(host.method, .icmp)
        XCTAssertNil(host.port)
    }

    func testHealthRequiresConsecutiveFailuresBeforeDown() {
        let hostID = UUID()
        let thresholds = LatencyThresholds(degradedMilliseconds: 80, downAfterFailures: 3)
        var health = HostHealth(hostID: hostID, thresholds: thresholds)

        health.ingest(.success(hostID: hostID, latency: .milliseconds(21)))
        XCTAssertEqual(health.status, .healthy)
        XCTAssertEqual(health.consecutiveFailureCount, 0)

        health.ingest(.failure(hostID: hostID, reason: .timeout))
        XCTAssertEqual(health.status, .degraded)
        XCTAssertEqual(health.consecutiveFailureCount, 1)

        health.ingest(.failure(hostID: hostID, reason: .dnsFailure))
        XCTAssertEqual(health.status, .degraded)
        XCTAssertEqual(health.consecutiveFailureCount, 2)

        health.ingest(.failure(hostID: hostID, reason: .connectionRefused))
        XCTAssertEqual(health.status, .down)
        XCTAssertEqual(health.consecutiveFailureCount, 3)
    }

    func testDefaultThresholdMarks107MillisecondsDegraded() {
        let hostID = UUID()
        var health = HostHealth(hostID: hostID, thresholds: .defaults)

        health.ingest(.success(hostID: hostID, latency: .milliseconds(107)))

        XCTAssertEqual(health.status, .degraded)
    }

    func testSampleSeriesBoundsSamplesAndComputesStats() {
        let hostID = UUID()
        var series = SampleSeries(hostID: hostID, capacity: 4)

        series.append(.success(hostID: hostID, latency: .milliseconds(10)))
        series.append(.success(hostID: hostID, latency: .milliseconds(20)))
        series.append(.failure(hostID: hostID, reason: .timeout))
        series.append(.success(hostID: hostID, latency: .milliseconds(40)))
        series.append(.success(hostID: hostID, latency: .milliseconds(50)))

        XCTAssertEqual(series.samples.count, 4)
        XCTAssertEqual(series.stats.transmitted, 4)
        XCTAssertEqual(series.stats.received, 3)
        XCTAssertEqual(series.stats.lossPercent, 25, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(series.stats.minimumMilliseconds), 20, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(series.stats.averageMilliseconds), 110.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(series.stats.maximumMilliseconds), 50, accuracy: 0.01)
    }

    func testMonitorSessionDurationValuesAreLimitedForIOSLiveActivity() {
        XCTAssertNil(MonitorSessionDuration.continuous.duration)
        XCTAssertEqual(MonitorSessionDuration.thirtySeconds.duration, .seconds(30))
        XCTAssertEqual(MonitorSessionDuration.oneMinute.duration, .seconds(60))
        XCTAssertEqual(MonitorSessionDuration.allCases, [.continuous, .thirtySeconds, .oneMinute])
        XCTAssertEqual(MonitorSessionDuration.continuous.displayName, "Live")
        XCTAssertEqual(MonitorSessionDuration.thirtySeconds.displayName, "30s")
        XCTAssertEqual(MonitorSessionDuration.oneMinute.displayName, "1m")
    }

    func testMonitorSessionStartsLiveAndComputesRemainingTime() {
        let hostID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let policy = MonitorSessionPolicy()

        let session = MonitorSessionState(
            hostID: hostID,
            duration: .thirtySeconds,
            startedAt: startedAt,
            policy: policy
        )

        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(1)), .live)
        XCTAssertEqual(session.remainingDuration(at: startedAt.addingTimeInterval(12)), .seconds(18))
        XCTAssertFalse(session.isExpired(at: startedAt.addingTimeInterval(29.9)))
    }

    func testMonitorSessionMarksStaleWhenLatestSampleAgesOut() {
        let hostID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let policy = MonitorSessionPolicy(liveFreshness: .seconds(10), staleAfter: .seconds(15), probeInterval: .seconds(2))
        let result = PingResult.success(
            hostID: hostID,
            latency: .milliseconds(12),
            timestamp: startedAt.addingTimeInterval(4)
        )

        let session = MonitorSessionState(
            hostID: hostID,
            duration: .oneMinute,
            startedAt: startedAt,
            latestResult: result,
            policy: policy
        )

        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(13)), .live)
        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(20)), .stale)
    }

    func testMonitorSessionEndsAtSelectedDuration() {
        let hostID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let session = MonitorSessionState(
            hostID: hostID,
            duration: .thirtySeconds,
            startedAt: startedAt,
            policy: MonitorSessionPolicy()
        )

        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(30)), .ended)
        XCTAssertTrue(session.isExpired(at: startedAt.addingTimeInterval(30)))
        XCTAssertEqual(session.remainingDuration(at: startedAt.addingTimeInterval(31)), .zero)
    }

    func testMonitorSessionContinuousDurationDoesNotExpireByTime() {
        let hostID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let session = MonitorSessionState(
            hostID: hostID,
            duration: .continuous,
            startedAt: startedAt,
            policy: MonitorSessionPolicy(staleAfter: .seconds(120))
        )

        XCTAssertNil(session.scheduledEndAt)
        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(60)), .live)
        XCTAssertFalse(session.isExpired(at: startedAt.addingTimeInterval(60 * 60)))
        XCTAssertEqual(session.remainingDuration(at: startedAt.addingTimeInterval(60)), .zero)
    }

    func testMonitorSessionCanEndEarlyOnIOSExpiration() {
        let hostID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let expiredAt = startedAt.addingTimeInterval(8)
        let session = MonitorSessionState(
            hostID: hostID,
            duration: .oneMinute,
            startedAt: startedAt,
            endedAt: expiredAt,
            endReason: .backgroundRuntimeExpired,
            policy: MonitorSessionPolicy()
        )

        XCTAssertEqual(session.phase(at: startedAt.addingTimeInterval(9)), .ended)
        XCTAssertEqual(session.endReason, .backgroundRuntimeExpired)
        XCTAssertEqual(session.remainingDuration(at: startedAt.addingTimeInterval(9)), .zero)
    }

    func testNotificationRulesCooldownAndRecovery() {
        let hostID = UUID()
        let rules = NotificationRuleSet(
            isEnabled: true,
            cooldown: .seconds(60),
            alertTypes: [.hostDown, .recovered, .highLatency],
            latencyThreshold: .milliseconds(100),
            notifyOnRecovery: true
        )
        var engine = AlertDecisionEngine(rules: rules)
        let base = Date(timeIntervalSince1970: 1_000)

        let highLatency = PingResult.success(hostID: hostID, latency: .milliseconds(125), timestamp: base)
        XCTAssertEqual(engine.evaluate(result: highLatency, previousStatus: .healthy, currentStatus: .degraded), .highLatency(hostID: hostID))

        let cooledDown = PingResult.success(hostID: hostID, latency: .milliseconds(180), timestamp: base.addingTimeInterval(30))
        XCTAssertNil(engine.evaluate(result: cooledDown, previousStatus: .degraded, currentStatus: .degraded))

        let down = PingResult.failure(hostID: hostID, reason: .timeout, timestamp: base.addingTimeInterval(90))
        XCTAssertEqual(engine.evaluate(result: down, previousStatus: .degraded, currentStatus: .down), .hostDown(hostID: hostID))

        let recovered = PingResult.success(hostID: hostID, latency: .milliseconds(20), timestamp: base.addingTimeInterval(170))
        XCTAssertEqual(engine.evaluate(result: recovered, previousStatus: .down, currentStatus: .healthy), .recovered(hostID: hostID))
    }

    func testNotificationRulesDetectNetworkChangeAndInternetLoss() {
        let hostID = UUID()
        let rules = NotificationRuleSet(
            isEnabled: true,
            cooldown: .seconds(60),
            alertTypes: [.networkChange, .internetLoss],
            latencyThreshold: .milliseconds(250),
            notifyOnRecovery: true
        )
        var engine = AlertDecisionEngine(rules: rules)
        let date = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(
            engine.evaluateNetworkChange(previousGateway: "192.168.1.1", currentGateway: "192.168.4.1", at: date),
            .networkChange(previousGateway: "192.168.1.1", currentGateway: "192.168.4.1")
        )

        let results = [PingResult.failure(hostID: hostID, reason: .timeout, timestamp: date.addingTimeInterval(90))]
        XCTAssertEqual(
            engine.evaluateInternetLoss(results: results, at: date.addingTimeInterval(90)),
            .internetLoss
        )
    }

    func testNotificationRulesRoundTripForSettingsPersistence() throws {
        let rules = NotificationRuleSet(
            isEnabled: true,
            cooldown: .seconds(120),
            alertTypes: [.hostDown, .recovered],
            latencyThreshold: .milliseconds(180),
            notifyOnRecovery: true
        )

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(NotificationRuleSet.self, from: data)

        XCTAssertEqual(decoded, rules)
        XCTAssertFalse(decoded.alertTypes.contains(.highLatency))
    }

    func testHostConfigIdentifiesLocalNetworkAddresses() {
        XCTAssertTrue(HostConfig(displayName: "Router", address: "192.168.1.1").requiresLocalNetworkPermission)
        XCTAssertTrue(HostConfig(displayName: "Link Local", address: "169.254.1.4").requiresLocalNetworkPermission)
        XCTAssertFalse(HostConfig(displayName: "Google", address: "8.8.8.8").requiresLocalNetworkPermission)
        XCTAssertFalse(HostConfig(displayName: "Domain", address: "example.com").requiresLocalNetworkPermission)
    }

    func testNetworkStatusPaletteIsSeparateFromPingHealth() {
        XCTAssertEqual(NetworkConnectivityStatus.connected.displayName, "Connected")
        XCTAssertEqual(NetworkConnectivityStatus.connected.defaultColorHex, "#7DC45B")
        XCTAssertEqual(NetworkConnectivityStatus.noInternet.defaultColorHex, "#F08A3C")
        XCTAssertEqual(NetworkConnectivityStatus.noIPAddress.defaultColorHex, "#FFD24A")
        XCTAssertEqual(NetworkConnectivityStatus.notConnected.defaultColorHex, "#F05B5F")
    }

    func testHostNotificationPolicyHasUserFacingLabels() {
        XCTAssertEqual(HostNotificationPolicy.inherit.displayName, "Use Global Settings")
        XCTAssertEqual(HostNotificationPolicy.enabled.displayName, "Always Notify")
        XCTAssertEqual(HostNotificationPolicy.muted.displayName, "Muted")
    }

    func testNetworkPerspectiveDiagnosesEverythingReachable() {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [host],
            healthByHost: [host.id: health(for: host, statusAfter: [.success(hostID: host.id, latency: .milliseconds(12))])]
        )

        XCTAssertEqual(diagnosis.scope, .allReachable)
        XCTAssertEqual(diagnosis.title, "Everything reachable")
    }

    func testNetworkPerspectivePrioritizesDefaultGatewayFailure() {
        let gateway = HostConfig(id: UUID(), displayName: "Default Gateway", address: "192.168.1.1", thresholds: LatencyThresholds(downAfterFailures: 1))
        let remote = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1", thresholds: LatencyThresholds(downAfterFailures: 1))
        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [gateway, remote],
            healthByHost: [
                gateway.id: health(for: gateway, statusAfter: [.failure(hostID: gateway.id, reason: .timeout)]),
                remote.id: health(for: remote, statusAfter: [.failure(hostID: remote.id, reason: .timeout)])
            ]
        )

        XCTAssertEqual(diagnosis.scope, .localNetwork)
        XCTAssertEqual(diagnosis.title, "Default gateway down")
        XCTAssertEqual(diagnosis.affectedHostIDs, [gateway.id])
    }

    func testNetworkPerspectiveDiagnosesUpstreamWhenLocalWorksAndAllRemoteFail() {
        let gateway = HostConfig(id: UUID(), displayName: "Default Gateway", address: "192.168.1.1", thresholds: LatencyThresholds(downAfterFailures: 1))
        let remote = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1", thresholds: LatencyThresholds(downAfterFailures: 1))
        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [gateway, remote],
            healthByHost: [
                gateway.id: health(for: gateway, statusAfter: [.success(hostID: gateway.id, latency: .milliseconds(3))]),
                remote.id: health(for: remote, statusAfter: [.failure(hostID: remote.id, reason: .timeout)])
            ]
        )

        XCTAssertEqual(diagnosis.scope, .upstream)
        XCTAssertEqual(diagnosis.title, "Upstream or ISP path down")
        XCTAssertEqual(diagnosis.affectedHostIDs, [remote.id])
    }

    func testNetworkPerspectiveDiagnosesIsolatedRemoteFailure() {
        let cloudflare = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1", thresholds: LatencyThresholds(downAfterFailures: 1))
        let google = HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8", thresholds: LatencyThresholds(downAfterFailures: 1))
        let diagnosis = NetworkPerspectiveDiagnoser().diagnose(
            hosts: [cloudflare, google],
            healthByHost: [
                cloudflare.id: health(for: cloudflare, statusAfter: [.failure(hostID: cloudflare.id, reason: .timeout)]),
                google.id: health(for: google, statusAfter: [.success(hostID: google.id, latency: .milliseconds(18))])
            ]
        )

        XCTAssertEqual(diagnosis.scope, .remoteService)
        XCTAssertEqual(diagnosis.title, "Remote host down")
        XCTAssertEqual(diagnosis.affectedHostIDs, [cloudflare.id])
    }

    func testAppStoreFlavorNormalizesUnsupportedICMPHosts() {
        let host = HostConfig(
            displayName: "Router ICMP",
            address: "192.168.1.1",
            method: .icmp,
            port: nil
        )

        let normalized = BuildFlavor.appStore.normalizedHost(host)

        XCTAssertEqual(normalized.id, host.id)
        XCTAssertEqual(normalized.displayName, "Router ICMP")
        XCTAssertEqual(normalized.address, "192.168.1.1")
        XCTAssertEqual(normalized.method, .tcp)
        XCTAssertEqual(normalized.port, 443)
    }

    func testDeveloperIDFlavorPreservesICMPHosts() {
        let host = HostConfig(
            displayName: "Router ICMP",
            address: "192.168.1.1",
            method: .icmp,
            port: nil
        )

        XCTAssertEqual(BuildFlavor.developerID.normalizedHost(host), host)
    }

    private func health(for host: HostConfig, statusAfter results: [PingResult]) -> HostHealth {
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        for result in results {
            health.ingest(result.withHostMetadata(from: host))
        }
        return health
    }
}
