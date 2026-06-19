import XCTest
@testable import PingScopeCore

final class HostTestingTests: XCTestCase {
    func testHostTesterMeasuresDraftWithoutMutatingStore() async {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let store = HostStore(defaultHosts: [.defaultInternet])
        let factory = SingleProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(18)))
        let tester = HostTester(probeFactory: factory)

        let result = await tester.test(host)
        let storedHosts = await store.hosts()

        XCTAssertEqual(result.latency?.milliseconds, 18)
        XCTAssertEqual(result.address, host.address)
        XCTAssertEqual(storedHosts.map(\.displayName), ["Cloudflare DNS"])
    }

    func testGatewayDetectorParsesDefaultGatewayFromRouteOutput() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en0
        """

        let gateway = DefaultGatewayDetector.parse(routeOutput: output)

        XCTAssertEqual(gateway, "192.168.1.1")
    }

    func testGatewayDetectorBuildsDefaultGatewayHost() {
        let host = DefaultGatewayDetector.gatewayHost(address: "192.168.1.1")

        XCTAssertEqual(host.displayName, "Default Gateway")
        XCTAssertEqual(host.address, "192.168.1.1")
        XCTAssertEqual(host.tier, .localGateway)
        XCTAssertEqual(host.method, .tcp)
        XCTAssertEqual(host.port, 80)
        XCTAssertTrue(host.requiresLocalNetworkPermission)
    }
}

private actor SingleProbeFactory: ProbeFactory {
    private let result: PingResult

    init(result: PingResult) {
        self.result = result
    }

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        SingleProbe(result: result)
    }
}

private struct SingleProbe: PingProbe {
    let result: PingResult

    func measure(_ host: HostConfig) async -> PingResult {
        result.withHostMetadata(from: host)
    }
}
