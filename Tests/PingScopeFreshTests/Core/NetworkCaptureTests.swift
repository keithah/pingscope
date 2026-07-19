import XCTest
@testable import PingScopeCore

final class NetworkCaptureTests: XCTestCase {
    func testInterfaceNormalizationMapsKnownAndUnknownLabels() {
        XCTAssertNil(NetworkInterfaceNormalizer.normalize(nil))
        XCTAssertEqual(NetworkInterfaceNormalizer.normalize(" Wi-Fi "), "wifi")
        XCTAssertEqual(NetworkInterfaceNormalizer.normalize("WLAN"), "wifi")
        XCTAssertEqual(NetworkInterfaceNormalizer.normalize("cell"), "cellular")
        XCTAssertEqual(NetworkInterfaceNormalizer.normalize("wiredEthernet"), "wired")
        XCTAssertEqual(NetworkInterfaceNormalizer.normalize("satellite"), "other")
    }

    func testInterfaceDisplayNamesProvideStableFallbacks() {
        XCTAssertEqual(NetworkInterfaceNormalizer.displayName(for: "wifi"), "Wi-Fi")
        XCTAssertEqual(NetworkInterfaceNormalizer.displayName(for: "cellular"), "Cellular")
        XCTAssertEqual(NetworkInterfaceNormalizer.displayName(for: "wired"), "Wired")
        XCTAssertEqual(NetworkInterfaceNormalizer.displayName(for: "other"), "Other")
    }

    func testCaptureFallsBackToInterfaceLabelWhenNameUnavailable() {
        let capture = NetworkCaptureSnapshot(interface: "wifi", name: nil)

        XCTAssertEqual(capture.interface, "wifi")
        XCTAssertEqual(capture.name, "Wi-Fi")
    }

    func testVPNHeuristicRecognizesTunnelPrefixesCaseInsensitively() {
        for interface in ["utun0", "tun1", "tap2", "ppp0", "ipsec0", "UTUN9"] {
            XCTAssertTrue(NetworkVPNHeuristic.isVPN(activeInterfaceNames: ["en0", interface]), interface)
        }
    }

    func testVPNHeuristicRejectsOrdinaryAndEmptyInterfaces() {
        XCTAssertFalse(NetworkVPNHeuristic.isVPN(activeInterfaceNames: []))
        XCTAssertFalse(NetworkVPNHeuristic.isVPN(activeInterfaceNames: ["en0", "pdp_ip0", "lo0"]))
    }

    func testNetworkCaptureStampsCopyAndKeepsLocationNetworkInSync() throws {
        let original = PingResult.success(
            hostID: UUID(),
            latency: .milliseconds(10),
            location: try XCTUnwrap(SampleLocation(
                latitude: 37,
                longitude: -122,
                networkName: "Old",
                networkInterface: "cellular"
            ))
        )
        let capture = NetworkCaptureSnapshot(
            interface: "wifi",
            name: "Office Wi-Fi",
            isVPN: true
        )

        let stamped = capture.stamping(original)

        XCTAssertNil(original.networkInterface)
        XCTAssertNil(original.networkName)
        XCTAssertFalse(original.isVPN)
        XCTAssertEqual(stamped.networkInterface, "wifi")
        XCTAssertEqual(stamped.networkName, "Office Wi-Fi")
        XCTAssertTrue(stamped.isVPN)
        XCTAssertEqual(stamped.location?.networkInterface, stamped.networkInterface)
        XCTAssertEqual(stamped.location?.networkName, stamped.networkName)
    }

    func testResolverUsesAuthorizedWiFiNameAndTunnelInterfaces() {
        let resolver = NetworkCaptureResolver(
            activeInterfaceNames: { ["en0", "utun3"] },
            wifiName: { "Office Wi-Fi" },
            cellularRadio: { nil }
        )

        let capture = resolver.snapshot(interface: "Wi-Fi", isWiFiNameAuthorized: true)

        XCTAssertEqual(capture.interface, "wifi")
        XCTAssertEqual(capture.name, "Office Wi-Fi")
        XCTAssertTrue(capture.isVPN)
    }

    func testResolverFallsBackWhenWiFiNameIsUnauthorizedOrBlank() {
        let resolver = NetworkCaptureResolver(
            activeInterfaceNames: { ["en0"] },
            wifiName: { "   " },
            cellularRadio: { nil }
        )

        XCTAssertEqual(
            resolver.snapshot(interface: "wifi", isWiFiNameAuthorized: false),
            NetworkCaptureSnapshot(interface: "wifi", name: "Wi-Fi")
        )
        XCTAssertEqual(
            resolver.snapshot(interface: "wifi", isWiFiNameAuthorized: true),
            NetworkCaptureSnapshot(interface: "wifi", name: "Wi-Fi")
        )
    }

    func testResolverBuildsCellularRadioLabel() {
        let resolver = NetworkCaptureResolver(
            activeInterfaceNames: { ["pdp_ip0"] },
            wifiName: { nil },
            cellularRadio: { "5G" }
        )

        let capture = resolver.snapshot(interface: "cellular", isWiFiNameAuthorized: false)

        XCTAssertEqual(capture.interface, "cellular")
        XCTAssertEqual(capture.name, "Cellular · 5G")
        XCTAssertFalse(capture.isVPN)
    }

    func testResolverUsesStableFallbackForWiredAndOtherInterfaces() {
        let resolver = NetworkCaptureResolver(
            activeInterfaceNames: { [] },
            wifiName: { "Ignored" },
            cellularRadio: { "Ignored" }
        )

        XCTAssertEqual(resolver.snapshot(interface: "ethernet").name, "Wired")
        XCTAssertEqual(resolver.snapshot(interface: "satellite").name, "Other")
    }
}
