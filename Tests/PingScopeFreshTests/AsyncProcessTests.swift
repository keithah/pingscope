import XCTest
@testable import PingScopeCore

final class AsyncProcessTests: XCTestCase {
    func testRunCapturesOutputWithConfiguredCap() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'abcdef'; printf '123456' >&2"],
            timeout: .seconds(1),
            maxOutputBytes: 4
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "abcd")
        XCTAssertEqual(String(data: result.standardError, encoding: .utf8), "1234")
    }

    func testRunTerminatesProcessOnTimeout() async throws {
        let start = ContinuousClock.now

        do {
            _ = try await AsyncProcess.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 5"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected AsyncProcess to time out")
        } catch AsyncProcessError.timedOut {
            let elapsed = start.duration(to: .now)
            XCTAssertLessThan(elapsed, .seconds(2))
        } catch {
            XCTFail("Expected timedOut, got \(error)")
        }
    }
}
