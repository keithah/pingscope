import Foundation
import PingScopeCore
import PingScopeiOS
import XCTest

final class IOSNotificationEngineTests: XCTestCase {
    func testNotificationRequestsMatchMacAlertSemantics() throws {
        let host = HostConfig(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            displayName: "Office DNS",
            address: "1.1.1.1"
        )
        let hosts = [host]

        XCTAssertEqual(
            PingScopeIOSNotificationRequest(decision: .hostDown(hostID: host.id), hosts: hosts),
            .init(title: "Office DNS is down", body: "PingScope has reached the configured failure threshold.")
        )
        XCTAssertEqual(
            PingScopeIOSNotificationRequest(decision: .recovered(hostID: host.id), hosts: hosts),
            .init(title: "Office DNS recovered", body: "Latency measurements are receiving responses again.")
        )
        XCTAssertEqual(
            PingScopeIOSNotificationRequest(decision: .highLatency(hostID: host.id), hosts: hosts),
            .init(title: "High latency on Office DNS", body: "Latency crossed the configured notification threshold.")
        )
        XCTAssertEqual(
            PingScopeIOSNotificationRequest(decision: .internetLoss, hosts: hosts),
            .init(title: "Internet connection lost", body: "All enabled hosts are currently failing.")
        )
    }

    func testAuthorizedAndProvisionalCentersScheduleButUnauthorizedCentersDoNot() async {
        for authorization in [
            PingScopeIOSNotificationAuthorization.authorized,
            .provisional,
            .denied,
            .notDetermined
        ] {
            let center = RecordingIOSNotificationCenter(authorization: authorization)
            let host = makeHost()
            let engine = PingScopeIOSNotificationEngine(center: center, hosts: [host])
            await engine.ingest(
                failure(host: host, at: Date(timeIntervalSince1970: 1)),
                previousStatus: .healthy,
                currentStatus: .down
            )

            let requests = await center.requests()
            if authorization == .authorized || authorization == .provisional {
                XCTAssertEqual(requests.map(\.title), ["Test Host is down"])
            } else {
                XCTAssertTrue(requests.isEmpty)
            }
        }
    }

    func testCoreRulesHostPolicyAndCooldownGateScheduledNotifications() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        var muted = makeHost()
        muted.notifications = .muted
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(cooldown: .seconds(300), alertTypes: [.hostDown]),
            hosts: [muted]
        )
        let start = Date(timeIntervalSince1970: 1_000)

        await engine.ingest(failure(host: muted, at: start), previousStatus: .healthy, currentStatus: .down)
        var requests = await center.requests()
        XCTAssertTrue(requests.isEmpty)

        var enabled = muted
        enabled.notifications = .inherit
        await engine.update(hosts: [enabled], includesAllHosts: false)
        await engine.ingest(failure(host: enabled, at: start), previousStatus: .healthy, currentStatus: .down)
        await engine.ingest(failure(host: enabled, at: start.addingTimeInterval(30)), previousStatus: .healthy, currentStatus: .down)
        await engine.ingest(failure(host: enabled, at: start.addingTimeInterval(301)), previousStatus: .healthy, currentStatus: .down)

        requests = await center.requests()
        XCTAssertEqual(requests.map(\.title), ["Test Host is down", "Test Host is down"])
    }

    func testFocusedHostDownThenRecoverySchedulesOneOfEach() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let host = makeHost()
        let engine = PingScopeIOSNotificationEngine(center: center, hosts: [host])
        let start = Date(timeIntervalSince1970: 1_500)

        await engine.ingest(failure(host: host, at: start), previousStatus: .healthy, currentStatus: .down)
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(20), timestamp: start.addingTimeInterval(1)),
            previousStatus: .down,
            currentStatus: .healthy
        )

        let requests = await center.requests()
        XCTAssertEqual(requests.map(\.title), ["Test Host is down", "Test Host recovered"])
    }

    func testAuthorizationRequestIsForwardedOnlyWhileNotDetermined() async {
        let undecidedCenter = RecordingIOSNotificationCenter(
            authorization: .notDetermined,
            requestAuthorizationResult: true
        )
        let undecidedEngine = PingScopeIOSNotificationEngine(center: undecidedCenter)
        let undecidedResult = await undecidedEngine.requestAuthorizationIfNeeded()
        let undecidedRequestCount = await undecidedCenter.authorizationRequestCount()
        let undecidedStatusCallCount = await undecidedCenter.authorizationStatusCallCount()
        XCTAssertTrue(undecidedResult)
        XCTAssertEqual(undecidedRequestCount, 1)
        XCTAssertEqual(undecidedStatusCallCount, 2)

        let authorizedCenter = RecordingIOSNotificationCenter(authorization: .authorized)
        let authorizedEngine = PingScopeIOSNotificationEngine(center: authorizedCenter)
        let authorizedResult = await authorizedEngine.requestAuthorizationIfNeeded()
        let authorizedRequestCount = await authorizedCenter.authorizationRequestCount()
        let authorizedStatusCallCount = await authorizedCenter.authorizationStatusCallCount()
        XCTAssertTrue(authorizedResult)
        XCTAssertEqual(authorizedRequestCount, 0)
        XCTAssertEqual(authorizedStatusCallCount, 1)
    }

    func testHighLatencyUsesCoreConsecutiveSampleRule() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let host = makeHost()
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(
                cooldown: .seconds(300),
                alertTypes: [.highLatency],
                latencyThreshold: .milliseconds(250),
                highLatencyConsecutiveSamples: 3
            ),
            hosts: [host]
        )

        for offset in 0..<3 {
            let result = PingResult.success(
                hostID: host.id,
                latency: .milliseconds(300),
                timestamp: Date(timeIntervalSince1970: Double(offset))
            )
            await engine.ingest(result, previousStatus: .healthy, currentStatus: .healthy)
        }

        let requests = await center.requests()
        XCTAssertEqual(requests.map(\.title), ["High latency on Test Host"])
    }

    func testPersistedNotificationRuleSourceLoadsCustomRulesAndFallsBackToDefaults() throws {
        let suiteName = "IOSNotificationEngineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let customRules = NotificationRuleSet(
            isEnabled: true,
            cooldown: .seconds(17),
            alertTypes: [.highLatency],
            latencyThreshold: .milliseconds(432),
            highLatencyConsecutiveSamples: 7,
            notifyOnRecovery: false
        )
        defaults.set(try JSONEncoder().encode(customRules), forKey: "notificationRules")

        XCTAssertEqual(
            PingScopeIOSNotificationRuleSource.persistedRules(in: defaults),
            customRules
        )
        defaults.removeObject(forKey: "notificationRules")
        XCTAssertEqual(
            PingScopeIOSNotificationRuleSource.persistedRules(in: defaults),
            NotificationRuleSet()
        )
    }

    func testInjectedRulesAndMidRunUpdateChangeScheduledBehavior() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let host = makeHost()
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(
                cooldown: .zero,
                alertTypes: [.highLatency, .recovered],
                latencyThreshold: .milliseconds(400),
                highLatencyConsecutiveSamples: 2,
                notifyOnRecovery: false
            ),
            hosts: [host]
        )

        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 1)),
            previousStatus: .healthy,
            currentStatus: .down
        )
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(300), timestamp: Date(timeIntervalSince1970: 2)),
            previousStatus: .down,
            currentStatus: .healthy
        )
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(300), timestamp: Date(timeIntervalSince1970: 3)),
            previousStatus: .healthy,
            currentStatus: .healthy
        )
        let requestsBeforeUpdate = await center.requests()
        XCTAssertTrue(requestsBeforeUpdate.isEmpty)

        await engine.update(rules: NotificationRuleSet(
            cooldown: .zero,
            alertTypes: [.highLatency, .recovered],
            latencyThreshold: .milliseconds(250),
            highLatencyConsecutiveSamples: 2,
            notifyOnRecovery: true
        ))
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(300), timestamp: Date(timeIntervalSince1970: 4)),
            previousStatus: .healthy,
            currentStatus: .healthy
        )
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(300), timestamp: Date(timeIntervalSince1970: 5)),
            previousStatus: .healthy,
            currentStatus: .healthy
        )
        await engine.ingest(
            .success(hostID: host.id, latency: .milliseconds(20), timestamp: Date(timeIntervalSince1970: 6)),
            previousStatus: .down,
            currentStatus: .healthy
        )

        let requests = await center.requests()
        XCTAssertEqual(requests.map(\.title), ["High latency on Test Host", "Test Host recovered"])
    }

    func testAuthorizationIsCachedAcrossSamplesAndRefreshObservesDenialAndGrant() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let host = makeHost()
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(cooldown: .zero, alertTypes: [.hostDown]),
            hosts: [host]
        )

        var refreshedAuthorization = await engine.refreshAuthorization()
        XCTAssertEqual(refreshedAuthorization, .authorized)
        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 1)),
            previousStatus: .healthy,
            currentStatus: .down
        )
        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 2)),
            previousStatus: .healthy,
            currentStatus: .down
        )
        var authorizationStatusCallCount = await center.authorizationStatusCallCount()
        var requestCount = await center.requests().count
        XCTAssertEqual(authorizationStatusCallCount, 1)
        XCTAssertEqual(requestCount, 2)

        await center.setAuthorization(.denied)
        refreshedAuthorization = await engine.refreshAuthorization()
        XCTAssertEqual(refreshedAuthorization, .denied)
        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 3)),
            previousStatus: .healthy,
            currentStatus: .down
        )
        authorizationStatusCallCount = await center.authorizationStatusCallCount()
        requestCount = await center.requests().count
        XCTAssertEqual(authorizationStatusCallCount, 2)
        XCTAssertEqual(requestCount, 2)

        await center.setAuthorization(.authorized)
        refreshedAuthorization = await engine.refreshAuthorization()
        XCTAssertEqual(refreshedAuthorization, .authorized)
        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 4)),
            previousStatus: .healthy,
            currentStatus: .down
        )
        authorizationStatusCallCount = await center.authorizationStatusCallCount()
        requestCount = await center.requests().count
        XCTAssertEqual(authorizationStatusCallCount, 3)
        XCTAssertEqual(requestCount, 3)
    }

    func testAllHostsInternetLossSchedulesOnceAndNetworkChangeStaysOffByDefault() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let first = makeHost(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "First")
        let second = makeHost(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, name: "Second")
        let engine = PingScopeIOSNotificationEngine(center: center, hosts: [first, second], includesAllHosts: true)
        let date = Date(timeIntervalSince1970: 2_000)

        await engine.ingest(failure(host: first, at: date), previousStatus: .healthy, currentStatus: .down)
        await engine.ingest(failure(host: second, at: date), previousStatus: .healthy, currentStatus: .down)
        await engine.evaluateNetworkChange(previousGateway: "192.168.1.1", currentGateway: "10.0.0.1", at: date)

        let requests = await center.requests()
        XCTAssertEqual(requests.filter { $0.title == "Internet connection lost" }.count, 1)
        XCTAssertFalse(requests.contains { $0.title == "Network changed" })
    }

    func testStartingAReconfiguredAllHostsScopeDoesNotReuseStaleResultsForInternetLoss() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let first = makeHost(id: UUID(), name: "First")
        let second = makeHost(id: UUID(), name: "Second")
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(cooldown: .zero, alertTypes: [.internetLoss]),
            hosts: [first, second],
            includesAllHosts: true
        )
        let date = Date(timeIntervalSince1970: 2_500)

        await engine.ingest(failure(host: first, at: date), previousStatus: .healthy, currentStatus: .down)
        await engine.ingest(failure(host: second, at: date), previousStatus: .healthy, currentStatus: .down)
        await engine.update(hosts: [first, second], includesAllHosts: true)
        await engine.ingest(
            failure(host: first, at: date.addingTimeInterval(1)),
            previousStatus: .healthy,
            currentStatus: .down
        )

        let requests = await center.requests()
        XCTAssertEqual(requests.filter { $0.title == "Internet connection lost" }.count, 1)
    }

    func testDisabledRulesScheduleNothing() async {
        let center = RecordingIOSNotificationCenter(authorization: .authorized)
        let host = makeHost()
        let engine = PingScopeIOSNotificationEngine(
            center: center,
            rules: NotificationRuleSet(isEnabled: false),
            hosts: [host]
        )

        await engine.ingest(
            failure(host: host, at: Date(timeIntervalSince1970: 3_000)),
            previousStatus: .healthy,
            currentStatus: .down
        )

        let requests = await center.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeHost(id: UUID = UUID(), name: String = "Test Host") -> HostConfig {
        HostConfig(id: id, displayName: name, address: "1.1.1.1")
    }

    private func failure(host: HostConfig, at date: Date) -> PingResult {
        .failure(hostID: host.id, reason: .timeout, timestamp: date)
    }
}

private actor RecordingIOSNotificationCenter: PingScopeIOSNotificationScheduling {
    private var authorization: PingScopeIOSNotificationAuthorization
    private let authorizationAfterRequest: PingScopeIOSNotificationAuthorization?
    private let requestAuthorizationResult: Bool
    private var recordedRequests: [PingScopeIOSNotificationRequest] = []
    private var requestCount = 0
    private var authorizationStatusCount = 0

    init(
        authorization: PingScopeIOSNotificationAuthorization,
        requestAuthorizationResult: Bool? = nil,
        authorizationAfterRequest: PingScopeIOSNotificationAuthorization? = nil
    ) {
        self.authorization = authorization
        self.requestAuthorizationResult = requestAuthorizationResult
            ?? (authorization == .authorized || authorization == .provisional)
        self.authorizationAfterRequest = authorizationAfterRequest
            ?? (requestAuthorizationResult == true ? .authorized : nil)
    }

    func authorizationStatus() async -> PingScopeIOSNotificationAuthorization {
        authorizationStatusCount += 1
        return authorization
    }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        if let authorizationAfterRequest {
            authorization = authorizationAfterRequest
        }
        return requestAuthorizationResult
    }

    func schedule(_ request: PingScopeIOSNotificationRequest) async throws {
        recordedRequests.append(request)
    }

    func requests() -> [PingScopeIOSNotificationRequest] {
        recordedRequests
    }

    func authorizationRequestCount() -> Int {
        requestCount
    }

    func authorizationStatusCallCount() -> Int {
        authorizationStatusCount
    }

    func setAuthorization(_ authorization: PingScopeIOSNotificationAuthorization) {
        self.authorization = authorization
    }
}
