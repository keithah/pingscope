import Foundation
import XCTest

final class BuildGraphOptimizationTests: XCTestCase {
    func testMediumAndLargeWidgetsShipFiveHostKeyAndIndependentIdentityColoredSeries() throws {
        let root = try repositoryRoot()
        let components = try String(
            contentsOf: root.appendingPathComponent("PingScopeWidget/Views/WidgetComponents.swift"),
            encoding: .utf8
        )
        let medium = try String(
            contentsOf: root.appendingPathComponent("PingScopeWidget/Views/MediumWidgetView.swift"),
            encoding: .utf8
        )
        let large = try String(
            contentsOf: root.appendingPathComponent("PingScopeWidget/Views/LargeWidgetView.swift"),
            encoding: .utf8
        )
        let widgetData = try String(
            contentsOf: root.appendingPathComponent("PingScopeWidget/WidgetData.swift"),
            encoding: .utf8
        )
        let keyStart = try XCTUnwrap(components.range(of: "struct WidgetHostKey"))
        let graphStart = try XCTUnwrap(
            components.range(
                of: "struct WidgetMultiHostLatencyGraph",
                range: keyStart.upperBound..<components.endIndex
            )
        )
        let colorExtensionStart = try XCTUnwrap(
            components.range(
                of: "private extension WidgetGraphDisplayColor",
                range: graphStart.upperBound..<components.endIndex
            )
        )
        let keySource = components[keyStart.lowerBound..<graphStart.lowerBound]
        let graphSource = components[graphStart.lowerBound..<colorExtensionStart.lowerBound]

        XCTAssertTrue(components.contains("struct WidgetHostKey"))
        XCTAssertTrue(components.contains("struct WidgetMultiHostLatencyGraph"))
        XCTAssertTrue(components.contains("ForEach(presentation.series"))
        XCTAssertTrue(components.contains("series.displayColor"))
        XCTAssertTrue(components.contains("presentation.timeWindow"))
        XCTAssertTrue(components.contains("presentation.latencyScale"))
        XCTAssertTrue(medium.contains("WidgetHostKey(presentation:"))
        XCTAssertTrue(medium.contains("WidgetMultiHostLatencyGraph(presentation:"))
        XCTAssertFalse(medium.contains("snapshot.hosts.prefix(3)"))
        XCTAssertTrue(large.contains("WidgetHostKey(presentation:"))
        XCTAssertTrue(large.contains("WidgetMultiHostLatencyGraph(presentation:"))
        XCTAssertTrue(large.contains("WidgetLargeFamilyLayout(hostCount:"))
        XCTAssertTrue(large.contains("presentation.legend.prefix(layout.detailRowCount)"))
        XCTAssertTrue(keySource.contains(".accessibilityLabel(\"\\(entry.displayName),"))
        XCTAssertFalse(keySource.contains(".accessibilityLabel(presentation.accessibilityLabel)"))
        XCTAssertTrue(graphSource.contains(".accessibilityLabel(presentation.accessibilityLabel)"))
        XCTAssertTrue(widgetData.contains("displayColor: $0.displayColor.map"))
    }

    func testHostEditorsShipCustomAndAutomaticColorControls() throws {
        let root = try repositoryRoot()
        let iosDraft = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSHostDraft.swift"),
            encoding: .utf8
        )
        let iosEditor = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSHostEditorView.swift"),
            encoding: .utf8
        )
        let macModel = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeApp/PingScopeModel.swift"),
            encoding: .utf8
        )
        let macEditor = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeApp/SettingsRootView+Hosts.swift"),
            encoding: .utf8
        )
        let colorBinding = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeCore/HostDisplayColor.swift"),
            encoding: .utf8
        )
        let iosApp = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(iosDraft.contains("var displayColor: HostDisplayColor?"))
        XCTAssertTrue(iosDraft.contains("var usesAutomaticDisplayColor: Bool"))
        XCTAssertTrue(iosEditor.contains("ColorPicker(\"Host Color\", selection:"))
        XCTAssertTrue(iosEditor.contains("Button(\"Use Automatic Color\")"))
        XCTAssertTrue(iosEditor.contains("colorEditor.selectOpaqueSRGB"))
        XCTAssertTrue(macModel.contains("var draftDisplayColor: HostDisplayColor?"))
        XCTAssertTrue(macEditor.contains("ColorPicker(\"Host Color\", selection:"))
        XCTAssertTrue(macEditor.contains("Button(\"Use Automatic Color\")"))
        XCTAssertTrue(macEditor.contains("editor.selectOpaqueSRGB"))
        XCTAssertTrue(colorBinding.contains("struct HostDisplayColorEditorBinding"))
        XCTAssertTrue(colorBinding.contains("color.converted(to: colorSpace"))
        XCTAssertTrue(iosApp.contains("sessionModel.reconcileFocusedHostEdit"))
    }

    func testIOSConnectivityTipsShippingWiring() throws {
        let root = try repositoryRoot()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )
        let shellSource = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(appSource.contains("@Published var connectivityTipsEnabled: Bool"))
        XCTAssertTrue(appSource.contains("UserDefaults.standard.pingScopeIOSConnectivityTipsEnabled = connectivityTipsEnabled"))
        XCTAssertTrue(appSource.contains("self.connectivityTipsEnabled = UserDefaults.standard.pingScopeIOSConnectivityTipsEnabled"))
        XCTAssertTrue(appSource.contains("connectivityTipsEnabled: model.connectivityTipsEnabled"))
        XCTAssertTrue(appSource.contains("onSetConnectivityTipsEnabled: { isEnabled in\n                    model.connectivityTipsEnabled = isEnabled"))

        XCTAssertTrue(shellSource.contains("var pingScopeIOSConnectivityTipsEnabled: Bool"))
        XCTAssertTrue(shellSource.contains("Toggle(\"Connectivity Tips\", isOn: Binding("))
        XCTAssertTrue(shellSource.contains("set: { onSetConnectivityTipsEnabled($0) }"))
        XCTAssertTrue(shellSource.contains("connectivityTipsEnabled: connectivityTipsEnabled"))
    }

    func testIOSLiveActivityPreferencesShipHonestSettingsAndLifecycleWiring() throws {
        let root = try repositoryRoot()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )
        let shellSource = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
            encoding: .utf8
        )
        let extensionSource = try String(
            contentsOf: root.appendingPathComponent("PingScopeLiveActivity/PingScopeLiveActivityBundle.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("liveActivityOwnershipCoordinator.setMasterEnabled(isEnabled)"))
        XCTAssertTrue(appSource.contains("liveActivityOwnershipCoordinator.pauseOwnedIfAllowed"))
        XCTAssertTrue(appSource.contains("showsDynamicIslandDetails: liveActivityPreferences.dynamicIslandDetailsEnabled"))
        XCTAssertTrue(shellSource.contains("Section(\"Live Activity\")"))
        XCTAssertTrue(shellSource.contains("Toggle(\"Lock Screen Live Activity\""))
        XCTAssertTrue(shellSource.contains("Toggle(\"Dynamic Island Details\""))
        XCTAssertTrue(shellSource.contains(".disabled(!lockScreenLiveActivityEnabled)"))
        XCTAssertTrue(shellSource.contains("controls the Live Activity on both the Lock Screen and Dynamic Island"))
        XCTAssertTrue(shellSource.contains("cannot remove the system surface independently"))
        XCTAssertTrue(extensionSource.contains("dynamicIslandRegionDecisions(contentState: context.state).expanded"))
        XCTAssertTrue(extensionSource.contains("dynamicIslandRegionDecisions(contentState: context.state).compactLeading"))
        XCTAssertTrue(extensionSource.contains("dynamicIslandRegionDecisions(contentState: context.state).compactTrailing"))
        XCTAssertTrue(extensionSource.contains("dynamicIslandRegionDecisions(contentState: context.state).minimal"))
        XCTAssertTrue(extensionSource.contains("case .statusOnly:"))
        XCTAssertTrue(extensionSource.contains("identityColor(for: row.identityColor)"))
    }

    func testEverySatisfiedIOSPathUpdateUsesGatewayHostUpdateDecision() throws {
        let source = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(source.components(separatedBy: "pathMonitor.pathUpdateHandler =").count - 1, 1)

        let handlerStart = try XCTUnwrap(source.range(of: "pathMonitor.pathUpdateHandler ="))
        let handlerEnd = try XCTUnwrap(
            source.range(of: "pathMonitor.start(queue:", range: handlerStart.upperBound..<source.endIndex)
        )
        let handler = source[handlerStart.lowerBound..<handlerEnd.lowerBound]
        let satisfiedGuard = try XCTUnwrap(handler.range(of: "guard path.status == .satisfied else { return }"))
        let refresh = try XCTUnwrap(handler.range(of: "model.refreshDefaultGatewayHost(", range: satisfiedGuard.upperBound..<handler.endIndex))
        XCTAssertLessThan(satisfiedGuard.lowerBound, refresh.lowerBound)

        let decisionStart = try XCTUnwrap(source.range(of: "private func refreshDefaultGatewayHost("))
        let decisionEnd = try XCTUnwrap(
            source.range(of: "private var defaultGatewayHostIndex:", range: decisionStart.upperBound..<source.endIndex)
        )
        let decisionRoute = source[decisionStart.lowerBound..<decisionEnd.lowerBound]
        XCTAssertTrue(decisionRoute.contains("sessionModel.gatewayHostUpdate("))
        XCTAssertFalse(decisionRoute.contains("detectedHost.address != lastGatewayAddress"))
    }

    func testIOSFocusedLaunchHydratesAndMarksPeerRowsCachedWithinBoundedHistory() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("await refreshFocusedPeerPresentation()"))
        XCTAssertTrue(source.contains("Date().addingTimeInterval(-24 * 60 * 60)"))
        let refreshStart = try XCTUnwrap(source.range(of: "private func refreshFocusedPeerPresentation() async"))
        let nextFunctionStart = try XCTUnwrap(
            source.range(of: "private func refreshRangedHistory(", range: refreshStart.upperBound..<source.endIndex)
        )
        let focusedRefresh = source[refreshStart.lowerBound..<nextFunctionStart.lowerBound]
        XCTAssertTrue(focusedRefresh.contains("applyFocusedPeerPresentation(PingScopeIOSFocusedPeerPresentation("))
        XCTAssertTrue(focusedRefresh.contains("selectedHostID: requestedHostID"))
        XCTAssertFalse(focusedRefresh.contains("health.ingest(sample)"))
    }

    func testIOSFocusedHostSwitchNeutralizesRowsBeforePublishingIdentityAndNilStoreRebuilds() throws {
        let source = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )
        let switchStart = try XCTUnwrap(source.range(of: "private func switchToHostAsync("))
        let allHostsSwitchStart = try XCTUnwrap(
            source.range(of: "private func switchToAllHostsAsync(", range: switchStart.upperBound..<source.endIndex)
        )
        let focusedSwitch = source[switchStart.lowerBound..<allHostsSwitchStart.lowerBound]
        let transition = try XCTUnwrap(focusedSwitch.range(of: "PingScopeIOSFocusedPeerPresentation.transitioning("))
        let scopePublish = try XCTUnwrap(focusedSwitch.range(of: "self.hostScope = .focused"))
        let identityPublish = try XCTUnwrap(focusedSwitch.range(of: "self.snapshot = LiveMonitorSessionSnapshot("))

        XCTAssertTrue(focusedSwitch.contains("outgoingHostID: self.snapshot.host.id"))
        XCTAssertTrue(focusedSwitch.contains("outgoingSamples: self.snapshot.series.samples"))
        XCTAssertLessThan(transition.lowerBound, scopePublish.lowerBound)
        XCTAssertLessThan(transition.lowerBound, identityPublish.lowerBound)

        let historyStart = try XCTUnwrap(source.range(of: "private func refreshHistory(force:"))
        let peerRefreshStart = try XCTUnwrap(
            source.range(of: "private func refreshFocusedPeerPresentation()", range: historyStart.upperBound..<source.endIndex)
        )
        let refreshHistory = source[historyStart.lowerBound..<peerRefreshStart.lowerBound]
        let nilStore = try XCTUnwrap(refreshHistory.range(of: "guard let historyStore else"))
        let cutoff = try XCTUnwrap(refreshHistory.range(of: "let cutoff =", range: nilStore.upperBound..<refreshHistory.endIndex))
        let nilStoreBranch = refreshHistory[nilStore.lowerBound..<cutoff.lowerBound]

        XCTAssertTrue(nilStoreBranch.contains("applyFocusedPeerPresentation("))
        XCTAssertTrue(nilStoreBranch.contains("PingScopeIOSFocusedPeerPresentation("))
    }

    func testIOSOtherHostsAndHostsTabRenderAccessibleCachedLatencyAndMiniGraphs() throws {
        let source = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
            encoding: .utf8
        )
        let otherHostsStart = try XCTUnwrap(source.range(of: "private func otherHostsCard("))
        let monitorRowsStart = try XCTUnwrap(
            source.range(of: "private func monitorHostRows(", range: otherHostsStart.upperBound..<source.endIndex)
        )
        let hostsTabStart = try XCTUnwrap(source.range(of: "private var hostsTab: some View"))
        let historyTabStart = try XCTUnwrap(
            source.range(of: "private var historyTab: some View", range: hostsTabStart.upperBound..<source.endIndex)
        )
        let rowStart = try XCTUnwrap(source.range(of: "private func allHostsRow("))
        let sectionHeaderStart = try XCTUnwrap(
            source.range(of: "private func sectionHeader(", range: rowStart.upperBound..<source.endIndex)
        )
        let otherHosts = source[otherHostsStart.lowerBound..<monitorRowsStart.lowerBound]
        let hostsTab = source[hostsTabStart.lowerBound..<historyTabStart.lowerBound]
        let shippingRow = source[rowStart.lowerBound..<sectionHeaderStart.lowerBound]

        XCTAssertTrue(otherHosts.contains("cachedRows[host.id]"))
        XCTAssertTrue(otherHosts.contains("allHostsRow("))
        XCTAssertTrue(otherHosts.contains("action: .focus"))
        XCTAssertTrue(hostsTab.contains("cachedRows[listedHost.id]"))
        XCTAssertTrue(hostsTab.contains("allHostsRow("))
        XCTAssertTrue(hostsTab.contains("action: .edit"))
        XCTAssertTrue(shippingRow.contains("PingScopeIOSSparkline(renderData: graphData"))
        XCTAssertTrue(shippingRow.contains("Text(presentation.latencyText)"))
        XCTAssertTrue(shippingRow.contains("if let cacheLabel = presentation.cacheLabel"))
        XCTAssertTrue(shippingRow.contains("Text(cacheLabel)"))
        XCTAssertTrue(shippingRow.contains(".accessibilityLabel(presentation.accessibilityLabel)"))
    }

    func testIOSHostSwitcherUsesStandardTelemetryRowsInSavedOrder() throws {
        let source = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
            encoding: .utf8
        )
        let switcherStart = try XCTUnwrap(source.range(of: "private var hostSwitcher: some View"))
        let allHostsRowStart = try XCTUnwrap(
            source.range(of: "private func allHostsSwitcherRow(", range: switcherStart.upperBound..<source.endIndex)
        )
        let switcher = source[switcherStart.lowerBound..<allHostsRowStart.lowerBound]

        XCTAssertTrue(switcher.contains("PingScopeIOSSwitchHostPresentation("))
        XCTAssertTrue(switcher.contains("ForEach(switcherPresentation.items)"))
        XCTAssertTrue(switcher.contains("let allHostsGraphPresentation = allHostsGraphPresentationMemo.resolve"))
        XCTAssertTrue(switcher.contains("allHostsRow("))
        XCTAssertTrue(switcher.contains("allHostsGraphPresentation: switcherPresentation.allHostsGraphPresentation"))
        XCTAssertTrue(switcher.contains("isSelected: concreteItem.isSelected"))
        XCTAssertFalse(switcher.contains("showsSparkline: false"))
    }

    func testIOSMonitorSettingsOmitsSessionStatusButKeepsRunControl() throws {
        let source = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Sources/PingScopeiOS/PingScopeIOSShell.swift"),
            encoding: .utf8
        )
        let settingsStart = try XCTUnwrap(source.range(of: "private var monitorSettings: some View"))
        let tabBarStart = try XCTUnwrap(
            source.range(of: "private var floatingTabBar: some View", range: settingsStart.upperBound..<source.endIndex)
        )
        let settings = source[settingsStart.lowerBound..<tabBarStart.lowerBound]

        XCTAssertFalse(settings.contains("Section(\"Session\")"))
        XCTAssertFalse(source.contains("private var remainingText: String"))
        XCTAssertTrue(source.contains("private var runControl: some View"))
        XCTAssertTrue(source.contains("Text(\"Live\").tag(Optional(MonitorSessionDuration.continuous))"))
    }

    func testAppStoreSchemeDoesNotBuildDeveloperIDApp() throws {
        let root = try repositoryRoot()
        let scheme = try String(contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme"), encoding: .utf8)
        XCTAssertFalse(scheme.contains("BlueprintName = \"PingScopeApp\""), "App Store scheme should not build the Developer ID app target")
    }

    func testSwiftPMUsesModuleAlignedTestTargets() throws {
        let manifest = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let expectedTargets: [(String, [String], String)] = [
            ("PingScopeCoreTests", ["PingScopeCore"], "Tests/PingScopeFreshTests/Core"),
            ("PingScopeHistoryKitTests", ["PingScopeCore", "PingScopeHistoryKit"], "Tests/PingScopeFreshTests/History"),
            ("PingScopeCloudSyncTests", ["PingScopeCore", "PingScopeCloudSync", "PingScopeObjCExceptionBoundary"], "Tests/PingScopeFreshTests/Cloud"),
            ("PingScopeiOSTests", ["PingScopeCore", "PingScopeHistoryKit", "PingScopeiOS"], "Tests/PingScopeFreshTests/iOS"),
            ("PingScopeMacAppTests", ["PingScopeCore", "PingScopeHistoryKit", "PingScope"], "Tests/PingScopeFreshTests/MacApp"),
            ("PingScopeExtensionSupportTests", ["PingScopeCore", "PingScopeExtensionSupport"], "Tests/PingScopeFreshTests/ExtensionSupport"),
            ("PingScopeBuildGraphTests", [], "Tests/PingScopeFreshTests/BuildGraph")
        ]

        XCTAssertEqual(expectedTargets.count, 7, "Every module-aligned test target must be guarded")

        for (name, dependencies, path) in expectedTargets {
            XCTAssertTrue(manifest.contains("name: \"\(name)\""), "Missing \(name)")
            let dependencyList = dependencies.map { "\"\($0)\"" }.joined(separator: ", ")
            XCTAssertTrue(
                manifest.contains("dependencies: [\(dependencyList)]"),
                "\(name) should declare only [\(dependencyList)]"
            )
            XCTAssertTrue(manifest.contains("path: \"\(path)\""), "\(name) should retain its isolated path")
        }
        XCTAssertFalse(manifest.contains("name: \"PingScopeTests\""), "Monolithic test target remains")
    }

    func testSwiftPMTargetPathsCompileEveryPackageSourceExactlyOnce() throws {
        let root = try repositoryRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let targetPaths = [
            "Sources/PingScopeExtensionSupport",
            "Sources/PingScopeCore",
            "Sources/PingScopeCloudSync",
            "Sources/PingScopeHistoryKit",
            "Sources/PingScopeLiveActivitySupport",
            "Sources/PingScopeiOS",
            "Sources/PingScopeApp",
            "Sources/PingScopeExportValidate",
            "Sources/PingScopeProbeValidate",
        ]

        XCTAssertFalse(manifest.contains("exclude:"), "Implicit target membership should not omit source files")
        XCTAssertFalse(manifest.contains("sources:"), "Implicit target membership should compile each target path recursively")
        for path in targetPaths {
            XCTAssertEqual(manifest.components(separatedBy: "path: \"\(path)\"").count - 1, 1, path)
        }

        let packageSources = try targetPaths.flatMap { path in
            try swiftSources(beneath: root.appendingPathComponent(path), relativeTo: root)
        }
        let allPackageEligibleSources = try swiftSources(
            beneath: root.appendingPathComponent("Sources"),
            relativeTo: root
        ).filter { !$0.hasPrefix("Sources/PingScopeiOSApp/") }

        XCTAssertEqual(packageSources.count, Set(packageSources).count, "A source is covered by more than one target path")
        XCTAssertEqual(Set(packageSources), Set(allPackageEligibleSources), "A SwiftPM source is orphaned or assigned outside its target path")
    }

    func testExtensionTargetsUseMinimalPackageProductsAndFrameworkPhases() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let widgetTarget = try targetBlock(named: "widgetExtension", in: project)
        let widgetFrameworks = try buildPhase(named: "Frameworks", for: widgetTarget, in: project)
        XCTAssertTrue(try targetDeclaresPackageProduct("PingScopeExtensionSupport", target: widgetTarget, in: project))
        XCTAssertTrue(try frameworkPhase(widgetFrameworks, linksPackageProduct: "PingScopeExtensionSupport", in: project))

        let liveActivityTarget = try targetBlock(named: "PingScopeLiveActivityExtension", in: project)
        let liveActivityFrameworks = try buildPhase(named: "Frameworks", for: liveActivityTarget, in: project)
        XCTAssertTrue(try targetDeclaresPackageProduct("PingScopeLiveActivitySupport", target: liveActivityTarget, in: project))
        XCTAssertTrue(try frameworkPhase(liveActivityFrameworks, linksPackageProduct: "PingScopeLiveActivitySupport", in: project))

        for productName in ["PingScopeCore", "PingScopeiOS", "PingScopeHistoryKit", "PingScopeCloudSync"] {
            XCTAssertFalse(try targetDeclaresPackageProduct(productName, target: widgetTarget, in: project), "Widget target links monolithic product \(productName)")
            XCTAssertFalse(try frameworkPhase(widgetFrameworks, linksPackageProduct: productName, in: project), "Widget framework phase links monolithic product \(productName)")
            XCTAssertFalse(try targetDeclaresPackageProduct(productName, target: liveActivityTarget, in: project), "Live Activity target links monolithic product \(productName)")
            XCTAssertFalse(try frameworkPhase(liveActivityFrameworks, linksPackageProduct: productName, in: project), "Live Activity framework phase links monolithic product \(productName)")
        }

        XCTAssertTrue(try packageProductBlock(named: "PingScopeExtensionSupport", in: project).contents.contains("isa = XCSwiftPackageProductDependency;"))
        XCTAssertTrue(try packageProductBlock(named: "PingScopeLiveActivitySupport", in: project).contents.contains("isa = XCSwiftPackageProductDependency;"))
        XCTAssertTrue(project.contains("path = PingScopeWidget;"), "Widget synchronized source group is missing")
        XCTAssertTrue(project.contains("path = PingScopeLiveActivity;"), "Live Activity synchronized source group is missing")
    }

    func testIOSAppBuildsAndEmbedsBothExtensionTargets() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let iosAppTarget = try targetBlock(named: "PingScopeiOSApp", in: project)
        let embedPhase = try buildPhase(named: "Embed App Extensions", for: iosAppTarget, in: project)

        XCTAssertTrue(try target(iosAppTarget, dependsOn: "PingScopeLiveActivityExtension", in: project), "iOS app must depend on Live Activity")
        XCTAssertTrue(try target(iosAppTarget, dependsOn: "widgetExtension", in: project), "iOS app must depend on Widget")
        XCTAssertTrue(embedPhase.contents.contains("PingScopeLiveActivityExtension.appex in Embed App Extensions"))
        XCTAssertTrue(embedPhase.contents.contains("widgetExtension.appex in Embed App Extensions"))
    }

    func testMacSchemesUseFlavorMatchedTestHosts() throws {
        let root = try repositoryRoot()
        let appStoreScheme = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme"),
            encoding: .utf8
        )
        let developerScheme = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-DeveloperID.xcscheme"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertFalse(appStoreScheme.contains("BlueprintName = \"PingScopeTests\""))
        XCTAssertFalse(appStoreScheme.contains("BlueprintName = \"PingScopeUITests\""))
        XCTAssertTrue(developerScheme.contains("BlueprintName = \"PingScopeTests\""))
        XCTAssertTrue(
            developerScheme.contains("buildImplicitDependencies = \"NO\""),
            "The Developer ID test graph must use its explicit PingScopeApp dependency instead of discovering both mac app flavors"
        )
        XCTAssertTrue(project.contains("TEST_TARGET_NAME = PingScopeApp;"))
    }

    func testDeveloperIDReleaseValidatesAndEmbedsProvisioningProfileBeforeSigning() throws {
        let root = try repositoryRoot()
        let releaseScript = try String(
            contentsOf: root.appendingPathComponent("scripts/release-github.sh"),
            encoding: .utf8
        )
        let signingScript = try String(
            contentsOf: root.appendingPathComponent("deploy/sign-notarize.sh"),
            encoding: .utf8
        )
        let profileLibraryURL = root.appendingPathComponent("scripts/lib/developer-id-profile.sh")
        let profileLibrary = try String(contentsOf: profileLibraryURL, encoding: .utf8)

        XCTAssertTrue(releaseScript.contains("--provisioning-profile"))
        XCTAssertTrue(signingScript.contains("--provisioning-profile"))
        XCTAssertTrue(signingScript.contains("validate_developer_id_profile"))
        XCTAssertTrue(signingScript.contains("embed_developer_id_profile"))
        XCTAssertLessThan(
            try XCTUnwrap(signingScript.range(of: "embed_developer_id_profile")?.lowerBound),
            try XCTUnwrap(signingScript.range(of: "codesign_sign_macos_bundle_contents")?.lowerBound),
            "the profile must be embedded before the app signature is created"
        )
        XCTAssertTrue(profileLibrary.contains("com.hadm.PingScope"))
        XCTAssertTrue(profileLibrary.contains("ProvisionsAllDevices"))
        XCTAssertTrue(profileLibrary.contains("ExpirationDate"))
    }

    func testSparkleToolDiscoveryFindsResolvedXcodeArtifactsByDefault() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-sparkle-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let tool = temporaryRoot.appendingPathComponent(
            ".build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
        )
        try FileManager.default.createDirectory(
            at: tool.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "cd \"$2\"; source \"$1\"; find_sparkle_tool generate_keys",
            "pingscope-test",
            try repositoryRoot().appendingPathComponent("scripts/lib/sparkle-tools.sh").path,
            temporaryRoot.path,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let discoveredPath = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        XCTAssertEqual(process.terminationStatus, 0, discoveredPath)
        XCTAssertEqual(discoveredPath, ".build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys")
    }

    func testSoakCPUCheckCalculatesDutyCycleFromPSDurations() throws {
        let script = try repositoryRoot().appendingPathComponent("scripts/soak-cpu-check.sh").path
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "source \"$1\"; cpu_time_to_seconds 01:02:03; elapsed_time_to_seconds 1-02:03:04; duty_cycle_percent 3723 93784",
            "pingscope-test",
            script,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let values = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0, values)
        XCTAssertEqual(values.split(separator: "\n").map(String.init), ["3723.000", "93784.000", "3.970"])
    }

    func testReleaseVersionIsConsistentAcrossAllBuildConfigurations() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let marketingVersions = project
            .components(separatedBy: .newlines)
            .filter { $0.contains("MARKETING_VERSION =") }
        let buildVersions = project
            .components(separatedBy: .newlines)
            .filter { $0.contains("CURRENT_PROJECT_VERSION =") }

        XCTAssertFalse(marketingVersions.isEmpty)
        XCTAssertTrue(marketingVersions.allSatisfy { $0.contains("MARKETING_VERSION = 0.5.0;") })
        XCTAssertFalse(buildVersions.isEmpty)
        XCTAssertTrue(buildVersions.allSatisfy { $0.contains("CURRENT_PROJECT_VERSION = 94;") })
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func swiftSources(beneath directory: URL, relativeTo root: URL) throws -> [String] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return try enumerator.compactMap { element in
            guard let file = element as? URL, file.pathExtension == "swift" else { return nil }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return String(file.path.dropFirst(root.path.count + 1))
        }.sorted()
    }

    private struct PBXObject {
        let identifier: String
        let contents: String
    }

    private func targetBlock(named name: String, in project: String) throws -> PBXObject {
        try object(in: project) { block in
            block.contents.contains("isa = PBXNativeTarget;") && block.contents.contains("name = \(name);")
        }
    }

    private func packageProductBlock(named name: String, in project: String) throws -> PBXObject {
        try object(in: project) { block in
            block.contents.contains("isa = XCSwiftPackageProductDependency;") && block.contents.contains("productName = \(name);")
        }
    }

    private func buildPhase(named name: String, for target: PBXObject, in project: String) throws -> PBXObject {
        let identifier = try XCTUnwrap(reference(named: name, in: target.contents))
        return try objectBlock(identifier, in: project)
    }

    private func targetDeclaresPackageProduct(_ name: String, target: PBXObject, in project: String) throws -> Bool {
        target.contents.contains(try packageProductBlock(named: name, in: project).identifier)
    }

    private func frameworkPhase(_ phase: PBXObject, linksPackageProduct name: String, in project: String) throws -> Bool {
        let product = try packageProductBlock(named: name, in: project)
        return objectBlocks(in: project).contains { buildFile in
            buildFile.contents.contains("isa = PBXBuildFile;")
                && buildFile.contents.contains("productRef = \(product.identifier)")
                && phase.contents.contains(buildFile.identifier)
        }
    }

    private func target(_ target: PBXObject, dependsOn dependencyName: String, in project: String) throws -> Bool {
        let dependencyTarget = try targetBlock(named: dependencyName, in: project)
        return objectBlocks(in: project).contains { dependency in
            dependency.contents.contains("isa = PBXTargetDependency;")
                && dependency.contents.contains("target = \(dependencyTarget.identifier)")
                && target.contents.contains(dependency.identifier)
        }
    }

    private func reference(named name: String, in block: String) -> String? {
        block.split(separator: "\n").first { $0.contains("/* \(name) */") }?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init)
    }

    private func object(in project: String, where matches: (PBXObject) -> Bool) throws -> PBXObject {
        try XCTUnwrap(objectBlocks(in: project).first(where: matches))
    }

    private func objectBlock(_ identifier: String, in project: String) throws -> PBXObject {
        try object(in: project) { $0.identifier == identifier }
    }

    private func objectBlocks(in project: String) -> [PBXObject] {
        var blocks: [PBXObject] = []
        let lines = project.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index < lines.count {
            let line = String(lines[index])
            let identifier = line
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init)
            guard let identifier,
                  line.hasPrefix("\t\t"),
                  identifier.count == 24,
                  identifier.allSatisfy(\.isHexDigit) else {
                index += 1
                continue
            }
            var contents = line
            while !contents.trimmingCharacters(in: .whitespaces).hasSuffix("};"), index + 1 < lines.count {
                index += 1
                contents += "\n\(lines[index])"
            }
            blocks.append(PBXObject(identifier: identifier, contents: contents))
            index += 1
        }
        return blocks
    }
}
