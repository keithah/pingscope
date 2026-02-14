import XCTest
@testable import PingMonitor

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testStartupStateIsGrayWithNAText() {
        let viewModel = MenuBarViewModel()

        XCTAssertEqual(viewModel.status, .gray)
        XCTAssertEqual(viewModel.compactLatencyText, "N/A")
        XCTAssertNil(viewModel.menuBarState.lastRawLatencyMS)
    }

    func testHealthyAndWarningTransitions() {
        let viewModel = MenuBarViewModel(
            evaluator: MenuBarStatusEvaluator(healthyUpperBoundMS: 80, sustainedFailureThreshold: 3),
            smoother: LatencySmoother(alpha: 1.0, maxStepMS: 1_000)
        )

        viewModel.ingest(result: successResult(latencyMS: 42))
        XCTAssertEqual(viewModel.status, .green)
        XCTAssertEqual(viewModel.compactLatencyText, "42 ms")

        viewModel.ingest(result: successResult(latencyMS: 130))
        XCTAssertEqual(viewModel.status, .yellow)
        XCTAssertEqual(viewModel.compactLatencyText, "130 ms")
    }

    func testSustainedFailureTurnsRedAfterThreshold() {
        let viewModel = MenuBarViewModel(
            evaluator: MenuBarStatusEvaluator(healthyUpperBoundMS: 80, sustainedFailureThreshold: 3),
            smoother: LatencySmoother(alpha: 1.0, maxStepMS: 1_000)
        )

        viewModel.ingest(result: successResult(latencyMS: 40))
        XCTAssertEqual(viewModel.status, .green)

        viewModel.ingest(result: failureResult())
        XCTAssertEqual(viewModel.status, .gray)
        XCTAssertEqual(viewModel.compactLatencyText, "N/A")

        viewModel.ingest(result: failureResult())
        XCTAssertEqual(viewModel.status, .gray)

        viewModel.ingest(result: failureResult())
        XCTAssertEqual(viewModel.status, .red)
        XCTAssertEqual(viewModel.compactLatencyText, "N/A")
    }

    func testSmoothingReducesAbruptTextJumps() {
        let viewModel = MenuBarViewModel(
            evaluator: MenuBarStatusEvaluator(healthyUpperBoundMS: 80, sustainedFailureThreshold: 3),
            smoother: LatencySmoother(alpha: 0.5, maxStepMS: 20)
        )

        viewModel.ingest(result: successResult(latencyMS: 50))
        XCTAssertEqual(viewModel.compactLatencyText, "50 ms")
        XCTAssertEqual(viewModel.menuBarState.lastRawLatencyMS ?? 0, 50, accuracy: 0.001)

        viewModel.ingest(result: successResult(latencyMS: 200))
        XCTAssertEqual(viewModel.compactLatencyText, "70 ms")
        XCTAssertEqual(viewModel.menuBarState.lastRawLatencyMS ?? 0, 200, accuracy: 0.001)
    }

    private func successResult(latencyMS: Double) -> PingResult {
        PingResult(
            host: "8.8.8.8",
            port: 443,
            timestamp: Date(),
            latency: .milliseconds(latencyMS),
            error: nil
        )
    }

    private func failureResult() -> PingResult {
        PingResult(
            host: "8.8.8.8",
            port: 443,
            timestamp: Date(),
            latency: nil,
            error: .timeout
        )
    }
}
