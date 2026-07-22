import Foundation
import XCTest

final class CorePlatformImportGuardTests: XCTestCase {
    func testPingScopeCoreAndHistoryKitHaveNoPlatformFrameworkImports() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guardedSourceDirectories = [
            repositoryRoot.appendingPathComponent("Sources/PingScopeCore"),
            repositoryRoot.appendingPathComponent("Sources/PingScopeHistoryKit"),
        ]
        let forbiddenImports = [
            "import CoreLocation",
            "import NetworkExtension",
            "import CoreTelephony",
            "import CoreWLAN",
            "import MapKit",
            "import UIKit",
            "import AppKit",
            "import SwiftUI",
            "import UserNotifications",
        ]
        var violations: [String] = []

        for sourceDirectory in guardedSourceDirectories {
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: sourceDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            )
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for (offset, line) in contents.components(separatedBy: .newlines).enumerated() {
                    if forbiddenImports.contains(line.trimmingCharacters(in: .whitespaces)) {
                        violations.append("\(fileURL.lastPathComponent):\(offset + 1): \(line)")
                    }
                }
            }
        }

        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }

    func testApplicationHistoryRetentionCallSitesUseSharedPolicy() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iOSApp = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )
        let macApp = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/PingScopeApp/PingScopeModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(iOSApp.contains("retention: PingHistoryRetention.maximumDuration"))
        XCTAssertFalse(iOSApp.contains("retention: .days(30)"))
        XCTAssertTrue(macApp.contains("historyRetention = PingHistoryRetention.maximumDuration"))
    }

    func testAppStoreApplicationTargetsDeclareWiFiInfoCapability() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for filename in [
            "PingScope-iOS.entitlements",
            "PingScope-AppStore.entitlements",
        ] {
            let data = try Data(contentsOf: repositoryRoot
                .appendingPathComponent("Configuration")
                .appendingPathComponent(filename))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            XCTAssertEqual(
                plist["com.apple.developer.networking.wifi-info"] as? Bool,
                true,
                filename
            )
        }
    }

    func testDeveloperIDEntitlementsOmitCapabilitiesUnavailableToItsProvisioningProfile() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Configuration/PingScope-DeveloperID.entitlements"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(plist["com.apple.developer.networking.wifi-info"])
        XCTAssertEqual(
            plist["com.apple.developer.icloud-container-identifiers"] as? [String],
            ["iCloud.com.hadm.PingScope"]
        )
    }

    func testIOSAppWiresPersistedNotificationRulesAndRefreshesAuthorization() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iOSApp = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/PingScopeiOSApp/PingScopeIOSApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(iOSApp.contains("rules: PingScopeIOSNotificationRuleSource.persistedRules()"))
        XCTAssertTrue(iOSApp.contains("await notificationEngine.update(rules: PingScopeIOSNotificationRuleSource.persistedRules())"))
        XCTAssertTrue(iOSApp.contains("case .active:\n            runLifecycleTask { model, context in\n                await model.refreshNotificationConfiguration()"))
        XCTAssertTrue(iOSApp.contains("await notificationEngine.refreshAuthorization()"))
    }

    func testMacOSAndIOSNetworkInsightViewsDelegateToSharedPresentationSource() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let popoverViews = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/PingScopeApp/PopoverViews.swift"),
            encoding: .utf8
        )
        let popoverSupportViews = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/PingScopeApp/PopoverSupportViews.swift"),
            encoding: .utf8
        )
        let macView = popoverViews + popoverSupportViews
        let iosPresentation = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/PingScopeiOS/PingScopeIOSNetworkDiagnosisPresentation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(iosPresentation.contains("NetworkDiagnosisPresentation"))
        XCTAssertTrue(iosPresentation.contains("StarlinkTelemetryPresentation"))
        XCTAssertTrue(macView.contains("StarlinkTelemetryPresentation"))
        for duplicatedLiteral in [
            "\"network.slash\"",
            "\"wifi.exclamationmark\"",
            "\"exclamationmark.triangle.fill\"",
            "\"speedometer\"",
            "\"checkmark.circle.fill\"",
        ] {
            XCTAssertFalse(macView.contains(duplicatedLiteral), duplicatedLiteral)
            XCTAssertFalse(iosPresentation.contains(duplicatedLiteral), duplicatedLiteral)
        }
    }
}
