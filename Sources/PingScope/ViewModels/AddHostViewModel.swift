import Foundation

enum AddHostMode {
    case add
    case edit(Host)
}

@MainActor
final class AddHostViewModel: ObservableObject {
    enum TestResult: Equatable {
        case success(latencyMS: Double)
        case failed(error: String)
        case none
    }

    let mode: AddHostMode

    @Published var hostname: String = ""
    @Published var displayName: String = ""
    @Published var port: String = ""
    @Published var pingMethod: PingMethod = .tcp

    @Published var notificationsEnabled: Bool = true

    @Published var useCustomInterval: Bool = false
    @Published var intervalSeconds: String = ""
    @Published var useCustomTimeout: Bool = false
    @Published var timeoutSeconds: String = ""
    @Published var useCustomThresholds: Bool = false
    @Published var greenThresholdMS: String = ""
    @Published var yellowThresholdMS: String = ""

    @Published var isTesting: Bool = false
    @Published var testResult: TestResult? = nil
    @Published var showTestWarning: Bool = false

    let onSave: (Host) -> Void
    let onCancel: () -> Void

    private let pingService: PingService

    init(
        mode: AddHostMode,
        pingService: PingService = PingService(),
        onSave: @escaping (Host) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.pingService = pingService
        self.onSave = onSave
        self.onCancel = onCancel

        switch mode {
        case .add:
            break
        case let .edit(host):
            hostname = host.address
            displayName = host.name
            pingMethod = host.pingMethod
            notificationsEnabled = host.notificationsEnabled
            if host.port != host.pingMethod.defaultPort {
                port = String(host.port)
            }

            if let intervalOverride = host.intervalOverride {
                useCustomInterval = true
                intervalSeconds = Self.secondsString(for: intervalOverride)
            }

            if let timeoutOverride = host.timeoutOverride {
                useCustomTimeout = true
                timeoutSeconds = Self.secondsString(for: timeoutOverride)
            }

            if let greenOverride = host.greenThresholdMSOverride {
                useCustomThresholds = true
                greenThresholdMS = Self.numberString(for: greenOverride)
            }

            if let yellowOverride = host.yellowThresholdMSOverride {
                useCustomThresholds = true
                yellowThresholdMS = Self.numberString(for: yellowOverride)
            }
        }
    }

    var isValid: Bool {
        !trimmedHostname.isEmpty && !trimmedDisplayName.isEmpty
    }

    var portNumber: UInt16? {
        guard !trimmedPort.isEmpty, let parsed = UInt16(trimmedPort), parsed > 0 else {
            return nil
        }

        return parsed
    }

    var effectivePort: UInt16 {
        portNumber ?? pingMethod.defaultPort
    }

    func testPing() async {
        guard !trimmedHostname.isEmpty else {
            return
        }

        isTesting = true
        showTestWarning = false
        defer { isTesting = false }

        let host = buildHost()
        let result = await pingService.ping(host: host)

        if let latency = result.latency {
            testResult = .success(latencyMS: Self.durationToMilliseconds(latency))
            showTestWarning = false
        } else {
            testResult = .failed(error: Self.errorMessage(for: result.error))
            showTestWarning = true
        }
    }

    func save() {
        onSave(buildHost())
    }

    func cancel() {
        onCancel()
    }

    func reset() {
        hostname = ""
        displayName = ""
        port = ""
        pingMethod = .tcp
        notificationsEnabled = true

        useCustomInterval = false
        intervalSeconds = ""
        useCustomTimeout = false
        timeoutSeconds = ""
        useCustomThresholds = false
        greenThresholdMS = ""
        yellowThresholdMS = ""

        isTesting = false
        testResult = nil
        showTestWarning = false
    }

    private var trimmedHostname: String {
        hostname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPort: String {
        port.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildHost() -> Host {
        let intervalOverride = useCustomInterval ? Self.duration(from: intervalSeconds) : nil
        let timeoutOverride = useCustomTimeout ? Self.duration(from: timeoutSeconds) : nil
        let greenOverride = useCustomThresholds ? Self.positiveDouble(from: greenThresholdMS) : nil
        let yellowOverride = useCustomThresholds ? Self.positiveDouble(from: yellowThresholdMS) : nil

        switch mode {
        case .add:
            return Host(
                name: trimmedDisplayName,
                address: trimmedHostname,
                port: effectivePort,
                pingMethod: pingMethod,
                intervalOverride: intervalOverride,
                timeout: timeoutOverride,
                greenThresholdMSOverride: greenOverride,
                yellowThresholdMSOverride: yellowOverride,
                notificationsEnabled: notificationsEnabled,
                isDefault: false
            )
        case let .edit(existing):
            return Host(
                id: existing.id,
                name: trimmedDisplayName,
                address: trimmedHostname,
                port: effectivePort,
                pingMethod: pingMethod,
                intervalOverride: intervalOverride,
                timeout: timeoutOverride,
                greenThresholdMSOverride: greenOverride,
                yellowThresholdMSOverride: yellowOverride,
                notificationsEnabled: notificationsEnabled,
                isDefault: existing.isDefault
            )
        }
    }

    private static func duration(from value: String) -> Duration? {
        guard let seconds = positiveDouble(from: value) else {
            return nil
        }

        return .seconds(seconds)
    }

    private static func positiveDouble(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed > 0 else {
            return nil
        }

        return parsed
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let secondsMS = Double(components.seconds) * 1_000
        let attosecondsMS = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMS + attosecondsMS
    }

    private static func secondsString(for duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
        return numberString(for: seconds)
    }

    private static func numberString(for value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(value)
    }

    private static func errorMessage(for error: PingError?) -> String {
        guard let error else {
            return "Connection failed"
        }

        switch error {
        case .timeout:
            return "Connection timed out"
        case let .connectionFailed(message):
            return message
        case .cancelled:
            return "Connection cancelled"
        case .invalidHost:
            return "Invalid host configuration"
        }
    }
}
