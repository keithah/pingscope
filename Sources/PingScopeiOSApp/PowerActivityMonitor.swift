#if os(iOS)
import Foundation
import UIKit
import PingScopeCore

@MainActor
final class PowerActivityMonitor {
    private let onChange: (CadenceInputs) -> Void
    private var appBackgrounded = false
    private var lastReported: CadenceInputs?

    init(onChange: @escaping (CadenceInputs) -> Void) {
        self.onChange = onChange
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        report()
    }

    func setBackgrounded(_ backgrounded: Bool) {
        guard appBackgrounded != backgrounded else { return }
        appBackgrounded = backgrounded
        report()
    }

    @objc private func environmentChanged() { report() }

    private func currentThermalTier() -> ThermalTier {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private func report() {
        let inputs = CadenceInputs.combining(
            screenObscured: false,
            uiVisible: !appBackgrounded,
            appBackgrounded: appBackgrounded,
            powerSource: .unknown, // iOS has no user-facing AC/battery distinction we act on
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalTier: currentThermalTier()
        )
        guard inputs != lastReported else { return }
        lastReported = inputs
        onChange(inputs)
    }
}
#endif
