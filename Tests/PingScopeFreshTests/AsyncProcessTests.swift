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

    func testRunTerminatesProcessWhenSurroundingTaskCancelled() async throws {
        let start = ContinuousClock.now
        let task = Task {
            try? await AsyncProcess.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 5"]
            )
        }

        // Let the child start, then cancel the surrounding task.
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        _ = await task.value

        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(2), "Cancellation should terminate the child instead of waiting for sleep")
    }

    func testRunReportsNonZeroTerminationStatus() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 3"],
            timeout: .seconds(2)
        )

        XCTAssertEqual(result.terminationStatus, 3)
    }

    func testRunWithoutTimeoutReturnsCapturedOutput() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'hello'"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "hello")
    }

    func testRunDrainsOutputLargerThanPipeBufferWithoutDeadlock() async throws {
        // 200 KB exceeds the OS pipe buffer; capping output must not stall the child.
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero"],
            timeout: .seconds(5),
            maxOutputBytes: 10
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput.count, 10)
    }
}
