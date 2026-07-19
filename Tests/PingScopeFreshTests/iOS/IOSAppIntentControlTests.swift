import XCTest
import PingScopeCore
@testable import PingScopeiOS

final class IOSAppIntentControlTests: XCTestCase {
    func testHostResolverMatchesIDAndNormalizedName() {
        let home = HostConfig(displayName: "Home Gateway", address: "192.168.1.1")
        let office = HostConfig(displayName: "Office", address: "office.example.com")
        let hosts = [home, office]

        XCTAssertEqual(
            PingScopeIOSIntentHostResolver.resolve(
                PingScopeIOSIntentHostReference(id: home.id, name: "ignored"),
                in: hosts
            ),
            .found(home)
        )
        XCTAssertEqual(
            PingScopeIOSIntentHostResolver.resolve(
                PingScopeIOSIntentHostReference(name: "  hOmE gAtEwAy  "),
                in: hosts
            ),
            .found(home)
        )
    }

    func testHostResolverReturnsNotFoundForUnknownAndRemovedHosts() {
        let configured = HostConfig(displayName: "Configured", address: "example.com")
        let removedID = UUID()

        XCTAssertEqual(
            PingScopeIOSIntentHostResolver.resolve(
                PingScopeIOSIntentHostReference(name: "Missing"),
                in: [configured]
            ),
            .notFound
        )
        XCTAssertEqual(
            PingScopeIOSIntentHostResolver.resolve(
                PingScopeIOSIntentHostReference(id: removedID, name: "Configured"),
                in: [configured]
            ),
            .notFound
        )
    }

    func testStatusProjectionRepresentsFocusedAndAllHostsSnapshots() {
        let homeID = UUID()
        let serviceID = UUID()
        let focused = makeSnapshot(
            primaryHostID: homeID,
            hosts: [
                makeWidgetHost(id: homeID, name: "Home", isPrimary: true)
            ],
            health: [
                makeWidgetHealth(hostID: homeID, status: .healthy, latency: 18.4)
            ],
            monitoring: WidgetMonitoringContext(isActive: true, scope: .focused)
        )

        let focusedProjection = PingScopeIOSStatusIntentProjection(snapshot: focused)
        XCTAssertEqual(focusedProjection.mode, .focused)
        XCTAssertEqual(focusedProjection.title, "Home")
        XCTAssertEqual(focusedProjection.summary, "Healthy · 18 ms")
        XCTAssertEqual(focusedProjection.outputText, "Home: Healthy, 18 ms")
        XCTAssertEqual(focusedProjection.hosts, [
            PingScopeIOSIntentHostStatus(
                hostID: homeID,
                name: "Home",
                status: .healthy,
                latencyMilliseconds: 18.4
            )
        ])

        let allHosts = makeSnapshot(
            primaryHostID: homeID,
            hosts: [
                makeWidgetHost(id: homeID, name: "Home", isPrimary: true),
                makeWidgetHost(id: serviceID, name: "Service", isPrimary: false)
            ],
            health: [
                makeWidgetHealth(hostID: homeID, status: .healthy, latency: 18.4),
                makeWidgetHealth(hostID: serviceID, status: .degraded, latency: 220.2)
            ],
            monitoring: WidgetMonitoringContext(isActive: true, scope: .allHosts)
        )

        let allProjection = PingScopeIOSStatusIntentProjection(snapshot: allHosts)
        XCTAssertEqual(allProjection.mode, .allHosts)
        XCTAssertEqual(allProjection.title, "All Hosts")
        XCTAssertEqual(allProjection.summary, "2 hosts · Degraded")
        XCTAssertEqual(allProjection.hosts.map(\.name), ["Home", "Service"])
        XCTAssertEqual(
            allProjection.outputText,
            "All Hosts — Home: Healthy, 18 ms; Service: Degraded, 220 ms"
        )
    }

    func testStatusProjectionRepresentsEmptyAndMonitoringOffStates() {
        let empty = PingScopeIOSStatusIntentProjection(snapshot: nil)
        XCTAssertEqual(empty.mode, .empty)
        XCTAssertEqual(empty.title, "PingScope")
        XCTAssertEqual(empty.summary, "No monitoring data")
        XCTAssertEqual(empty.outputText, "No monitoring data")
        XCTAssertEqual(empty.hosts, [])

        let hostID = UUID()
        let off = PingScopeIOSStatusIntentProjection(snapshot: makeSnapshot(
            primaryHostID: hostID,
            hosts: [makeWidgetHost(id: hostID, name: "Home", isPrimary: true)],
            health: [makeWidgetHealth(hostID: hostID, status: .healthy, latency: 15)],
            monitoring: WidgetMonitoringContext(isActive: false, scope: .focused)
        ))
        XCTAssertEqual(off.mode, .monitoringOff)
        XCTAssertEqual(off.title, "Home")
        XCTAssertEqual(off.summary, "Monitoring is off")
        XCTAssertEqual(off.outputText, "Home — Monitoring is off")
    }

    func testStartStopDecisionSelectsFocusedAllHostsStopAndNoOpActions() {
        let selectedID = UUID()
        let requestedID = UUID()

        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .start(hostID: requestedID),
                current: PingScopeIOSIntentMonitoringState(
                    scope: .focused,
                    selectedHostID: selectedID,
                    isMonitoring: false
                )
            ),
            .startFocused(requestedID)
        )
        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .start(hostID: nil),
                current: PingScopeIOSIntentMonitoringState(
                    scope: .allHosts,
                    selectedHostID: selectedID,
                    isMonitoring: false
                )
            ),
            .startAllHosts
        )
        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .stop,
                current: PingScopeIOSIntentMonitoringState(
                    scope: .focused,
                    selectedHostID: selectedID,
                    isMonitoring: true
                )
            ),
            .stop
        )
        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .start(hostID: nil),
                current: PingScopeIOSIntentMonitoringState(
                    scope: .focused,
                    selectedHostID: selectedID,
                    isMonitoring: true
                )
            ),
            .none
        )
        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .stop,
                current: PingScopeIOSIntentMonitoringState(
                    scope: .focused,
                    selectedHostID: selectedID,
                    isMonitoring: false
                )
            ),
            .none
        )
    }

    func testStartDecisionSwitchesActiveMonitoringToRequestedHostWithoutRestarting() {
        let selectedID = UUID()
        let requestedID = UUID()

        XCTAssertEqual(
            PingScopeIOSIntentActionDecision.decide(
                request: .start(hostID: requestedID),
                current: PingScopeIOSIntentMonitoringState(
                    scope: .allHosts,
                    selectedHostID: selectedID,
                    isMonitoring: true
                )
            ),
            .switchToFocused(requestedID)
        )
    }

    func testControlProjectionReflectsMonitoringAndLatestPrimaryStatus() {
        let hostID = UUID()
        let active = makeSnapshot(
            primaryHostID: hostID,
            hosts: [makeWidgetHost(id: hostID, name: "Home", isPrimary: true)],
            health: [makeWidgetHealth(hostID: hostID, status: .degraded, latency: 145.7)],
            monitoring: WidgetMonitoringContext(isActive: true, scope: .focused)
        )

        XCTAssertEqual(
            PingScopeIOSControlStateProjection(snapshot: active),
            PingScopeIOSControlStateProjection(
                isMonitoring: true,
                statusText: "Home · Degraded · 146 ms",
                symbolName: "wave.3.right.circle.fill"
            )
        )
        XCTAssertEqual(
            PingScopeIOSControlStateProjection(snapshot: nil),
            PingScopeIOSControlStateProjection(
                isMonitoring: false,
                statusText: "No monitoring data",
                symbolName: "wave.3.right.circle"
            )
        )
    }

    func testControlKindsAreStableAcrossAppAndExtension() {
        XCTAssertEqual(PingScopeIOSControlKind.monitoring, "com.hadm.pingscope.monitoring-control")
        XCTAssertEqual(PingScopeIOSControlKind.status, "com.hadm.pingscope.status-control")
    }

    func testControlWidgetSourcesAreCompileTimeGatedToIOS() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controls = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PingScopeWidget/PingScopeControls.swift"),
            encoding: .utf8
        )
        let bundle = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PingScopeWidget/PingScopeWidget.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            controls.contains("#if os(iOS)\n@available(iOS 18.0, *)\nstruct PingScopeMonitoringControl"),
            "ControlWidget declarations must not be type-checked by the macOS 15 widget target"
        )
        XCTAssertTrue(
            bundle.contains("#if os(iOS)\n        if #available(iOS 18.0, *)"),
            "The shared WidgetBundle must only reference ControlWidget types on iOS"
        )
    }

    func testWidgetSnapshotMonitoringContextDecodesLegacyDataAsNil() throws {
        let json = """
        {
          "version": 1,
          "primaryHostID": null,
          "hosts": [],
          "health": [],
          "recentSamples": [],
          "networkStatus": "connected",
          "generatedAt": "2026-07-15T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.monitoring)
    }

    func testMonitoringStateParticipatesInWidgetStateEquality() {
        let hostID = UUID()
        let active = makeSnapshot(
            primaryHostID: hostID,
            hosts: [makeWidgetHost(id: hostID, name: "Home", isPrimary: true)],
            health: [makeWidgetHealth(hostID: hostID, status: .healthy, latency: 15)],
            monitoring: WidgetMonitoringContext(isActive: true, scope: .focused)
        )
        let stopped = WidgetSnapshot(
            primaryHostID: active.primaryHostID,
            hosts: active.hosts,
            health: active.health,
            recentSamples: active.recentSamples,
            networkStatus: active.networkStatus,
            generatedAt: active.generatedAt,
            monitoring: WidgetMonitoringContext(isActive: false, scope: .focused)
        )

        XCTAssertFalse(active.hasSameWidgetState(as: stopped))
    }

    func testIntentCommandStoreRoundTripsAndConsumesPendingRequestOnce() {
        let suiteName = "IOSAppIntentCommandTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PingScopeIOSIntentCommandStore(defaults: defaults)
        let request = PingScopeIOSIntentRequest.start(hostID: UUID())

        XCTAssertTrue(store.enqueue(request))
        XCTAssertEqual(store.takePending(), request)
        XCTAssertNil(store.takePending())
    }
}

private func makeSnapshot(
    primaryHostID: UUID?,
    hosts: [WidgetHost],
    health: [WidgetHostHealth],
    monitoring: WidgetMonitoringContext
) -> WidgetSnapshot {
    WidgetSnapshot(
        primaryHostID: primaryHostID,
        hosts: hosts,
        health: health,
        recentSamples: [],
        networkStatus: .connected,
        generatedAt: Date(timeIntervalSince1970: 1_752_580_800),
        monitoring: monitoring
    )
}

private func makeWidgetHost(id: UUID, name: String, isPrimary: Bool) -> WidgetHost {
    WidgetHost(
        id: id,
        displayName: name,
        address: "example.com",
        method: .https,
        port: 443,
        isPrimary: isPrimary
    )
}

private func makeWidgetHealth(
    hostID: UUID,
    status: HealthStatus,
    latency: Double?
) -> WidgetHostHealth {
    WidgetHostHealth(
        hostID: hostID,
        status: status,
        latencyMilliseconds: latency,
        consecutiveFailureCount: 0,
        failureReason: nil,
        latestResultAt: Date(timeIntervalSince1970: 1_752_580_800)
    )
}
