import Foundation
import PingScopeCore
import PingScopeHistoryKit
import PingScopeiOS
import XCTest

final class IOSDiagnosticsAndOnboardingTests: XCTestCase {
    func testDiagnosticsBundleContainsAppMetadataConfigurationAndLog() {
        let bundle = PingScopeIOSDiagnosticsBundle.text(
            metadata: .init(appName: "PingScope", version: "2.0", build: "200", buildFlavor: "App Store"),
            logText: "probe failed: timeout",
            hosts: [.defaultInternet],
            recentSamples: [],
            privacy: .redacted
        )

        XCTAssertTrue(bundle.contains("PingScope Diagnostics"))
        XCTAssertTrue(bundle.contains("App: PingScope"))
        XCTAssertTrue(bundle.contains("Version: 2.0 (200)"))
        XCTAssertTrue(bundle.contains("Build flavor: App Store"))
        XCTAssertTrue(bundle.contains("Cloudflare DNS · ICMP"))
        XCTAssertFalse(bundle.contains(HostConfig.defaultInternet.address))
        XCTAssertTrue(bundle.contains("probe failed: timeout"))
    }

    func testDiagnosticsBundleRedactsCoordinatesAndNetworkNamesWithoutExplicitOptIn() {
        let host = HostConfig.defaultInternet
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(24),
            timestamp: Date(timeIntervalSince1970: 1_000),
            location: SampleLocation(latitude: 37.3317, longitude: -122.0301),
            networkInterface: "wifi",
            networkName: "Office Wi-Fi"
        )
        let log = "sample latitude=37.3317 longitude=-122.0301 ssid=Office Wi-Fi"

        let bundle = PingScopeIOSDiagnosticsBundle.text(
            metadata: .init(appName: "PingScope", version: "2.0", build: "200", buildFlavor: "App Store"),
            logText: log,
            hosts: [host],
            recentSamples: [sample],
            privacy: .redacted
        )

        XCTAssertFalse(bundle.contains("37.3317"))
        XCTAssertFalse(bundle.contains("-122.0301"))
        XCTAssertFalse(bundle.contains("Office Wi-Fi"))
        XCTAssertTrue(bundle.contains("Network name: <redacted>"))
        XCTAssertTrue(bundle.contains("Location: <redacted>"))
    }

    func testDiagnosticsBundleMayIncludeCoordinatesAndNetworkNamesAfterExplicitOptIn() {
        let host = HostConfig.defaultInternet
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(24),
            timestamp: Date(timeIntervalSince1970: 1_000),
            location: SampleLocation(latitude: 37.3317, longitude: -122.0301),
            networkInterface: "wifi",
            networkName: "Office Wi-Fi"
        )

        let bundle = PingScopeIOSDiagnosticsBundle.text(
            metadata: .init(appName: "PingScope", version: "2.0", build: "200", buildFlavor: "App Store"),
            logText: "ssid=Office Wi-Fi latitude=37.3317 longitude=-122.0301",
            hosts: [host],
            recentSamples: [sample],
            privacy: .init(includesLocation: true, includesNetworkNames: true)
        )

        XCTAssertTrue(bundle.contains("37.3317"))
        XCTAssertTrue(bundle.contains("-122.0301"))
        XCTAssertTrue(bundle.contains("Office Wi-Fi"))
    }

    func testChecklistDerivesEveryItemFromItsAuthorizationOrCapability() throws {
        let needsAction = PingScopeIOSOnboardingPresentation(
            inputs: .init(
                notificationAuthorization: .denied,
                localNetworkCapability: .unavailable,
                locationAuthorization: .denied,
                isLocationTaggingEnabled: false,
                hasConfiguredWidget: false
            ),
            hasBeenSeen: false
        )

        XCTAssertEqual(needsAction.items.map(\.id), [.notifications, .localNetwork, .location, .widgets])
        XCTAssertTrue(needsAction.items.allSatisfy { $0.status == .needsAction })
        XCTAssertEqual(needsAction.overallStatus, .actionNeeded)
        XCTAssertTrue(needsAction.shouldPresentOnLaunch)

        let allSet = PingScopeIOSOnboardingPresentation(
            inputs: .init(
                notificationAuthorization: .provisional,
                localNetworkCapability: .available,
                locationAuthorization: .whenInUse,
                isLocationTaggingEnabled: true,
                hasConfiguredWidget: true
            ),
            hasBeenSeen: false
        )

        XCTAssertTrue(allSet.items.allSatisfy { $0.status == .satisfied })
        XCTAssertTrue(allSet.items.allSatisfy { $0.destination == nil })
        XCTAssertEqual(allSet.overallStatus, .allSet)
        XCTAssertFalse(allSet.shouldPresentOnLaunch)
    }

    func testChecklistTreatsUnusedLocalNetworkCapabilityAsSatisfied() throws {
        let presentation = PingScopeIOSOnboardingPresentation(
            inputs: .init(
                notificationAuthorization: .authorized,
                localNetworkCapability: .notRequired,
                locationAuthorization: .always,
                isLocationTaggingEnabled: true,
                hasConfiguredWidget: true
            ),
            hasBeenSeen: false
        )

        let localNetwork = try XCTUnwrap(presentation.items.first { $0.id == .localNetwork })
        XCTAssertEqual(localNetwork.status, .satisfied)
        XCTAssertEqual(localNetwork.detail, "Not needed by enabled hosts")
    }

    func testLocalNetworkCapabilityWaitsForEvidenceBeforeReportingUnavailable() {
        let localHost = HostConfig.defaultGateway
        let failedSample = PingResult.failure(
            hostID: localHost.id,
            reason: .timeout,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let successfulSample = PingResult.success(
            hostID: localHost.id,
            latency: .milliseconds(3),
            timestamp: Date(timeIntervalSince1970: 1_001)
        )

        XCTAssertEqual(
            PingScopeIOSLocalNetworkCapability.derive(hosts: [localHost], samples: []),
            .notRequired
        )
        XCTAssertEqual(
            PingScopeIOSLocalNetworkCapability.derive(hosts: [localHost], samples: [failedSample]),
            .unavailable
        )
        XCTAssertEqual(
            PingScopeIOSLocalNetworkCapability.derive(
                hosts: [localHost],
                samples: [failedSample, successfulSample]
            ),
            .available
        )
    }

    func testChecklistDoesNotRenagAfterItHasBeenSeen() {
        let presentation = PingScopeIOSOnboardingPresentation(
            inputs: .init(
                notificationAuthorization: .notDetermined,
                localNetworkCapability: .unavailable,
                locationAuthorization: .undetermined,
                isLocationTaggingEnabled: false,
                hasConfiguredWidget: false
            ),
            hasBeenSeen: true
        )

        XCTAssertEqual(presentation.overallStatus, .actionNeeded)
        XCTAssertFalse(presentation.shouldPresentOnLaunch)
    }

    func testOnboardingSeenPersistenceRoundTrips() throws {
        let suiteName = "IOSDiagnosticsAndOnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = PingScopeIOSOnboardingStore(defaults: defaults)

        XCTAssertFalse(first.hasBeenSeen)
        first.markSeen()

        let reloaded = PingScopeIOSOnboardingStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasBeenSeen)
    }

    @MainActor
    func testIOSHistoryExportReachabilityUsesPingHistoryStoreExportSamples() async throws {
        let store = IOSDiagnosticsHistoryExportStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HistoryStructuredExportService(temporaryDirectory: directory)
        let host = HostConfig.defaultInternet
        let now = Date(timeIntervalSince1970: 5_000)

        _ = try await service.export(store: store, host: host, range: .h24, format: .json, now: now)

        let recordedRequest = await store.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.host, host)
        XCTAssertEqual(request.since, HistoryRange.h24.cutoff(endingAt: now))
        XCTAssertEqual(request.format, .json)
    }
}

private actor IOSDiagnosticsHistoryExportStore: PingHistoryStore {
    struct Request: Sendable {
        let host: HostConfig
        let since: Date
        let format: HistoryExportFormat
    }

    private(set) var request: Request?

    func recordedRequest() -> Request? { request }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func exportSamples(
        host: HostConfig,
        since: Date,
        format: HistoryExportFormat,
        to url: URL
    ) async throws -> Int {
        request = Request(host: host, since: since, format: format)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: url)
        return 1
    }
}
