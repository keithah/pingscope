import Combine
import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var menuBarState: MenuBarState = .initial
    @Published private(set) var selectedHostSummary: String = "No host selected"
    @Published var isCompactModeEnabled: Bool
    @Published var isStayOnTopEnabled: Bool

    private let evaluator: MenuBarStatusEvaluator
    private let smoother: LatencySmoother

    private var consecutiveFailures = 0
    private var hasReceivedAnyResult = false
    private var isMonitoringActive = true
    private var smoothedLatencyMS: Double?
    private var activeGreenThresholdMS: Double = GlobalDefaults.default.greenThresholdMS
    private var activeYellowThresholdMS: Double = GlobalDefaults.default.yellowThresholdMS

    init(
        evaluator: MenuBarStatusEvaluator = MenuBarStatusEvaluator(),
        smoother: LatencySmoother = LatencySmoother(),
        isCompactModeEnabled: Bool = false,
        isStayOnTopEnabled: Bool = false
    ) {
        self.evaluator = evaluator
        self.smoother = smoother
        self.isCompactModeEnabled = isCompactModeEnabled
        self.isStayOnTopEnabled = isStayOnTopEnabled
    }

    var status: MenuBarStatus {
        menuBarState.status
    }

    var compactLatencyText: String {
        menuBarState.displayText
    }

    func setMonitoringActive(_ active: Bool) {
        isMonitoringActive = active
        updateState(displayLatencyMS: smoothedLatencyMS, rawLatencyMS: menuBarState.lastRawLatencyMS)
    }

    func setSelectedHost(_ host: Host, globalDefaults: GlobalDefaults) {
        selectedHostSummary = "\(host.name) (\(host.address))"
        activeGreenThresholdMS = host.effectiveGreenThresholdMS(globalDefaults)
        activeYellowThresholdMS = host.effectiveYellowThresholdMS(globalDefaults)
        updateState(displayLatencyMS: smoothedLatencyMS, rawLatencyMS: menuBarState.lastRawLatencyMS)
    }

    func ingest(result: PingResult) {
        hasReceivedAnyResult = true
        let rawLatencyMS = result.latency.map(Self.durationToMilliseconds)

        if result.isSuccess {
            consecutiveFailures = 0
            smoothedLatencyMS = smoother.next(previousMS: smoothedLatencyMS, rawMS: rawLatencyMS)
        } else {
            consecutiveFailures += 1
            smoothedLatencyMS = nil
        }

        updateState(displayLatencyMS: smoothedLatencyMS, rawLatencyMS: rawLatencyMS)
    }

    private func updateState(displayLatencyMS: Double?, rawLatencyMS: Double?) {
        let status = evaluator.evaluate(
            latencyMS: displayLatencyMS,
            greenThresholdMS: activeGreenThresholdMS,
            yellowThresholdMS: activeYellowThresholdMS,
            consecutiveFailures: consecutiveFailures,
            hasReceivedAnyResult: hasReceivedAnyResult,
            isMonitoringActive: isMonitoringActive
        )

        menuBarState = MenuBarState(
            displayText: Self.formatLatencyText(displayLatencyMS),
            status: status,
            lastRawLatencyMS: rawLatencyMS
        )
    }

    private static func formatLatencyText(_ latencyMS: Double?) -> String {
        guard let latencyMS else {
            return "N/A"
        }

        return "\(Int(latencyMS.rounded())) ms"
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let secondsMS = Double(components.seconds) * 1_000
        let attosecondsMS = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMS + attosecondsMS
    }
}
