import XCTest
@testable import PingScopeCore

final class HTTPSRoundTripProbeClassificationTests: XCTestCase {
    private let host = HostConfig(displayName: "Cloudflare", address: "1.1.1.1", method: .https, port: 443)

    private func measure(throwing error: any Error) async -> PingResult {
        await HTTPSRoundTripProbe(fetcher: ThrowingFetcher(error: error)).measure(host)
    }

    func testSuccessfulRoundTripReportsLatencyAndMetadata() async {
        let result = await HTTPSRoundTripProbe(fetcher: SucceedingFetcher()).measure(host)

        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(result.latency)
        XCTAssertEqual(result.metadata.note, "HTTPS response received")
        XCTAssertEqual(result.address, "1.1.1.1")
        XCTAssertEqual(result.port, 443)
    }

    func testTimedOutClassifiesAsTimeout() async {
        let result = await measure(throwing: URLError(.timedOut))
        XCTAssertEqual(result.failureReason, .timeout)
    }

    func testDNSErrorsClassifyAsDNSFailure() async {
        let cannotFind = await measure(throwing: URLError(.cannotFindHost))
        let lookupFailed = await measure(throwing: URLError(.dnsLookupFailed))
        XCTAssertEqual(cannotFind.failureReason, .dnsFailure)
        XCTAssertEqual(lookupFailed.failureReason, .dnsFailure)
    }

    func testConnectivityErrorsClassifyAsNetworkUnavailable() async {
        let cannotConnect = await measure(throwing: URLError(.cannotConnectToHost))
        let connectionLost = await measure(throwing: URLError(.networkConnectionLost))
        XCTAssertEqual(cannotConnect.failureReason, .networkUnavailable)
        XCTAssertEqual(connectionLost.failureReason, .networkUnavailable)
    }

    func testCancelledURLErrorClassifiesAsCancelled() async {
        let result = await measure(throwing: URLError(.cancelled))
        XCTAssertEqual(result.failureReason, .cancelled)
    }

    func testSwiftCancellationClassifiesAsCancelled() async {
        let result = await measure(throwing: CancellationError())
        XCTAssertEqual(result.failureReason, .cancelled)
    }

    func testUnrecognizedErrorClassifiesAsUnknownWithNotePreserved() async {
        let result = await measure(throwing: NSError(domain: "test", code: -1))
        XCTAssertEqual(result.failureReason, .unknown)
        XCTAssertNotNil(result.metadata.note)
    }
}

private struct ThrowingFetcher: HTTPSRoundTripFetching {
    let error: any Error

    func fetch(_ request: URLRequest) async throws {
        throw error
    }
}

private struct SucceedingFetcher: HTTPSRoundTripFetching {
    func fetch(_ request: URLRequest) async throws {}
}
