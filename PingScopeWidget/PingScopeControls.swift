import AppIntents
import PingScopeCore
import PingScopeiOS
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct PingScopeMonitoringControl: ControlWidget {
    static let kind = PingScopeIOSControlKind.monitoring

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: PingScopeControlValueProvider()) { state in
            ControlWidgetToggle(
                "PingScope Monitoring",
                isOn: state.isMonitoring,
                action: SetPingScopeMonitoringIntent()
            ) { isOn in
                Label(
                    isOn ? "Monitoring On" : "Monitoring Off",
                    systemImage: state.symbolName
                )
            }
        }
        .displayName("PingScope Monitoring")
        .description("Start or stop monitoring the current PingScope scope.")
    }
}

@available(iOS 18.0, *)
struct PingScopeStatusControl: ControlWidget {
    static let kind = PingScopeIOSControlKind.status

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: PingScopeControlValueProvider()) { state in
            ControlWidgetButton(action: OpenPingScopeStatusControlIntent()) {
                Label(state.statusText, systemImage: state.symbolName)
            }
        }
        .displayName("PingScope Status")
        .description("Show the latest status already published by PingScope.")
    }
}

@available(iOS 18.0, *)
private struct PingScopeControlValueProvider: ControlValueProvider {
    let previewValue = PingScopeIOSControlStateProjection(
        isMonitoring: false,
        statusText: "Monitoring Off",
        symbolName: "wave.3.right.circle"
    )

    func currentValue() async throws -> PingScopeIOSControlStateProjection {
        let snapshot = await WidgetSnapshotStore().load()
        return PingScopeIOSControlStateProjection(snapshot: snapshot)
    }
}

@available(iOS 18.0, *)
private struct SetPingScopeMonitoringIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set PingScope Monitoring"
    static let openAppWhenRun = true

    @Parameter(title: "Monitoring")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let request: PingScopeIOSIntentRequest = value ? .start(hostID: nil) : .stop
        guard PingScopeIOSIntentCommandStore().enqueue(request) else {
            throw PingScopeControlError.commandUnavailable
        }
        return .result()
    }
}

@available(iOS 18.0, *)
private struct OpenPingScopeStatusControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PingScope Status"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

private enum PingScopeControlError: LocalizedError {
    case commandUnavailable

    var errorDescription: String? {
        "PingScope could not save the monitoring request."
    }
}
