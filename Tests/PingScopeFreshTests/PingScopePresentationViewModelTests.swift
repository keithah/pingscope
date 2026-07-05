import XCTest
@testable import PingScope
import PingScopeCore

@MainActor
final class PingScopePresentationViewModelTests: XCTestCase {
    func testOverlayPresentationViewModelRefreshesOverlayPreferences() {
        let oldShowsAllHosts = UserDefaults.standard.overlayShowsAllHosts
        let oldShowsLegend = UserDefaults.standard.overlayShowsLegend
        defer {
            UserDefaults.standard.overlayShowsAllHosts = oldShowsAllHosts
            UserDefaults.standard.overlayShowsLegend = oldShowsLegend
        }

        let model = PingScopeModel()
        model.overlayShowsAllHosts = false
        model.overlayShowsLegend = false

        let viewModel = OverlayPresentationViewModel(model: model)
        XCTAssertFalse(viewModel.presentation.showsAllHosts)
        XCTAssertFalse(viewModel.presentation.showsLegend)

        viewModel.selectAllHosts()
        viewModel.toggleLegend()

        XCTAssertTrue(model.overlayShowsAllHosts)
        XCTAssertTrue(model.overlayShowsLegend)
        XCTAssertTrue(viewModel.presentation.showsAllHosts)
        XCTAssertTrue(viewModel.presentation.showsLegend)
    }

    func testStatusPopoverPresentationViewModelRefreshesRangeAndHostMode() {
        let oldPopoverShowsAllHosts = UserDefaults.standard.popoverShowsAllHosts
        defer {
            UserDefaults.standard.popoverShowsAllHosts = oldPopoverShowsAllHosts
        }

        let model = PingScopeModel()
        model.selectedRange = .fiveMinutes
        model.popoverShowsAllHosts = false

        let viewModel = StatusPopoverPresentationViewModel(model: model)
        XCTAssertEqual(viewModel.presentation.selectedRange, .fiveMinutes)
        XCTAssertFalse(viewModel.presentation.popoverShowsAllHosts)

        viewModel.setSelectedRange(.oneHour)
        viewModel.selectAllHosts()

        XCTAssertEqual(model.selectedRange, .oneHour)
        XCTAssertTrue(model.popoverShowsAllHosts)
        XCTAssertEqual(viewModel.presentation.selectedRange, .oneHour)
        XCTAssertTrue(viewModel.presentation.popoverShowsAllHosts)
    }

    func testSavingDraftHostOptimisticallyUpdatesVisibleSnapshot() {
        let oldHostConfigs = UserDefaults.standard.hostConfigs
        let oldPrimaryHostID = UserDefaults.standard.primaryHostID
        defer {
            UserDefaults.standard.hostConfigs = oldHostConfigs
            UserDefaults.standard.primaryHostID = oldPrimaryHostID
        }

        let model = PingScopeModel()
        let hostID = HostConfig.defaultInternet.id

        model.selectHostForEditing(hostID)
        model.draftIntervalMilliseconds = 30_000
        model.addDraftHost()

        let savedHost = model.snapshot.hosts.first { $0.id == hostID }
        XCTAssertEqual(savedHost?.interval, .milliseconds(30_000))
    }

    func testWidgetSnapshotPublishQueuePersistsLatestSnapshot() async throws {
        let oldWidgetsEnabled = UserDefaults.standard.widgetsEnabled
        let oldWidgetSharingOptedIn = UserDefaults.standard.widgetSharingOptedIn
        let suiteName = "pingscope-model-widget-tests-\(UUID().uuidString)"
        let inspectionDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            UserDefaults.standard.widgetsEnabled = oldWidgetsEnabled
            UserDefaults.standard.widgetSharingOptedIn = oldWidgetSharingOptedIn
            inspectionDefaults.removePersistentDomain(forName: suiteName)
        }

        let model = PingScopeModel()
        model.widgetSnapshotStore = WidgetSnapshotStore(suiteName: suiteName, key: "snapshot")
        model.widgetsEnabled = true
        let host = HostConfig(displayName: "Edge", address: "1.1.1.1")

        model.publishWidgetSnapshot(runtimeSnapshot(host: host, latencyMilliseconds: 12))
        model.publishWidgetSnapshot(runtimeSnapshot(host: host, latencyMilliseconds: 34))
        await model.widgetSnapshotPublishTask?.value

        let saved = await model.widgetSnapshotStore?.load()
        XCTAssertEqual(saved?.health.first?.latencyMilliseconds, 34)
    }

    func testGatewayObservationEnablesLocalNetworkAndSyncsResolvedHost() {
        let oldAllowsLocalNetworkProbes = UserDefaults.standard.allowsLocalNetworkProbes
        defer {
            UserDefaults.standard.allowsLocalNetworkProbes = oldAllowsLocalNetworkProbes
        }
        let model = PingScopeModel()
        model.allowsLocalNetworkProbes = false
        let gateway = DefaultGatewayDetector.gatewayHost(address: "192.168.1.1")

        model.handleGatewayObservation(.detected(gateway), resolvedHost: gateway)

        XCTAssertTrue(model.allowsLocalNetworkProbes)
    }

    func testStarlinkDetectionEnablesLocalNetworkForDetectedDish() {
        let oldAllowsLocalNetworkProbes = UserDefaults.standard.allowsLocalNetworkProbes
        defer {
            UserDefaults.standard.allowsLocalNetworkProbes = oldAllowsLocalNetworkProbes
        }
        let model = PingScopeModel()
        model.allowsLocalNetworkProbes = false

        model.reconcileStarlinkDetection(.detected(.defaultStarlinkDish), removeMissing: false)

        XCTAssertTrue(model.allowsLocalNetworkProbes)
    }

    private func runtimeSnapshot(host: HostConfig, latencyMilliseconds: Double) -> RuntimeSnapshot {
        let result = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(latencyMilliseconds),
            timestamp: Date(timeIntervalSince1970: latencyMilliseconds)
        ).withHostMetadata(from: host)
        var health = HostHealth(hostID: host.id)
        health.ingest(result)
        var series = SampleSeries(hostID: host.id)
        series.append(result)
        return RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [host.id: health],
            samplesByHost: [host.id: series]
        )
    }
}
