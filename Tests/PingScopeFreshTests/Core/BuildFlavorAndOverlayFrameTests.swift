import XCTest
@testable import PingScopeCore

final class BuildFlavorDetectionTests: XCTestCase {
    func testMacHostEditorMethodSourceIncludesHTTPSWithDefaultPort() {
        XCTAssertTrue(BuildFlavor.developerID.availableMethods.contains(.https))
        XCTAssertTrue(BuildFlavor.appStore.availableMethods.contains(.https))
        XCTAssertEqual(PingMethod.https.defaultPort, 443)
    }
    private let bundleURL = URL(fileURLWithPath: "/Applications/PingScope.app", isDirectory: true)

    private func detect(
        hasCompileFlag: Bool = false,
        receiptSuffix: String? = nil,
        sandboxContainerID: String? = nil
    ) -> BuildFlavor {
        BuildFlavor.detect(
            hasCompileFlag: hasCompileFlag,
            bundleURL: bundleURL,
            fileExists: { url in
                guard let receiptSuffix else { return false }
                return url.path.hasSuffix(receiptSuffix)
            },
            sandboxContainerID: sandboxContainerID
        )
    }

    func testCompileFlagAloneMarksAppStore() {
        XCTAssertEqual(detect(hasCompileFlag: true), .appStore)
    }

    func testMacAppStoreReceiptMarksAppStore() {
        XCTAssertEqual(detect(receiptSuffix: "Contents/_MASReceipt/receipt"), .appStore)
    }

    func testMacTestFlightSandboxReceiptMarksAppStore() {
        XCTAssertEqual(detect(receiptSuffix: "Contents/_MASReceipt/sandboxReceipt"), .appStore)
    }

    func testIOSStoreKitSandboxReceiptMarksAppStore() {
        XCTAssertEqual(detect(receiptSuffix: "StoreKit/sandboxReceipt"), .appStore)
    }

    func testSandboxContainerWithoutReceiptMarksAppStore() {
        // A store build whose receipt has not materialized yet must still hide
        // ICMP: the sandbox denies the ping helper regardless of receipt state.
        XCTAssertEqual(detect(sandboxContainerID: "com.hadm.PingScope"), .appStore)
    }

    func testNoFlagNoReceiptNoSandboxIsDeveloperID() {
        XCTAssertEqual(detect(), .developerID)
    }

    func testAppStoreFlavorNeverOffersICMP() {
        XCTAssertFalse(BuildFlavor.appStore.availableMethods.contains(.icmp))
        XCTAssertFalse(PingMethod.appStoreAvailableCases.contains(.icmp))
        XCTAssertTrue(BuildFlavor.developerID.availableMethods.contains(.icmp))
    }

    func testAppStoreFlavorNormalizesICMPHostsToTCP() {
        let host = HostConfig(displayName: "Gateway", address: "192.168.1.1", method: .icmp, port: nil)
        XCTAssertEqual(BuildFlavor.appStore.normalizedHost(host).method, .tcp)
        XCTAssertEqual(BuildFlavor.developerID.normalizedHost(host).method, .icmp)
    }
}

final class OverlayFrameClampingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1144)
    private let minVisible = CGSize(width: 60, height: 24)
    private let overlaySize = CGSize(width: 240, height: 96)

    func testFullyOffScreenFrameClampsBackWithinScreen() {
        let frame = CGRect(origin: CGPoint(x: 5000, y: 5000), size: overlaySize)
        let clamped = clampedOverlayFrame(frame, into: [screen], minVisible: minVisible)
        XCTAssertEqual(clamped, CGRect(x: 1560, y: 1048, width: 240, height: 96))
        XCTAssertTrue(screen.contains(clamped ?? .zero))
    }

    func testSliverBelowVisibilityThresholdClamps() {
        // Only 10pt of width on-screen: enabled in Settings, unusable in practice.
        let frame = CGRect(x: 1790, y: 500, width: 240, height: 96)
        let clamped = clampedOverlayFrame(frame, into: [screen], minVisible: minVisible)
        XCTAssertEqual(clamped, CGRect(x: 1560, y: 500, width: 240, height: 96))
    }

    func testSufficientlyVisibleFrameIsNotMoved() {
        let frame = CGRect(x: 80, y: 620, width: 240, height: 96)
        XCTAssertNil(clampedOverlayFrame(frame, into: [screen], minVisible: minVisible))
    }

    func testFrameLargerThanScreenPinsToScreenOrigin() {
        let frame = CGRect(x: 5000, y: 5000, width: 3000, height: 2000)
        let clamped = clampedOverlayFrame(frame, into: [screen], minVisible: minVisible)
        XCTAssertEqual(clamped?.origin, screen.origin)
    }

    func testFrameVisibleOnSecondaryScreenIsNotMoved() {
        let secondary = CGRect(x: 1800, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2400, y: 300, width: 240, height: 96)
        XCTAssertNil(clampedOverlayFrame(frame, into: [screen, secondary], minVisible: minVisible))
    }

    func testOffAllScreensClampsIntoPreferredFirstScreen() {
        let secondary = CGRect(x: 1800, y: 0, width: 1920, height: 1080)
        let frame = CGRect(origin: CGPoint(x: -4000, y: -4000), size: overlaySize)
        let clamped = clampedOverlayFrame(frame, into: [secondary, screen], minVisible: minVisible)
        XCTAssertEqual(clamped, CGRect(x: 1800, y: 0, width: 240, height: 96))
        XCTAssertTrue(secondary.contains(clamped ?? .zero))
    }

    func testNoScreensReturnsNil() {
        let frame = CGRect(origin: .zero, size: overlaySize)
        XCTAssertNil(clampedOverlayFrame(frame, into: [], minVisible: minVisible))
    }
}
