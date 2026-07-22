#if os(macOS)
import AppKit
import Foundation
import IOKit.ps
import PingScopeCore

/// Observes macOS power/thermal/screen state and reports a debounced
/// ``CadenceInputs`` whenever any input changes. All state is touched on the
/// main actor; `onChange` is invoked on the main actor.
@MainActor
final class MacPowerActivityMonitor {
    private let onChange: (CadenceInputs) -> Void
    private var screenAsleep = false
    private var screenLocked = false
    private var uiVisible = true
    private var runLoopSource: CFRunLoopSource?
    private var lastReported: CadenceInputs?

    init(onChange: @escaping (CadenceInputs) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        installPowerSourceObserver()
        report()
    }

    func setUIVisible(_ visible: Bool) {
        guard uiVisible != visible else { return }
        uiVisible = visible
        report()
    }

    @objc func screenDidSleep() { screenAsleep = true; report() }
    @objc func screenDidWake() { screenAsleep = false; report() }
    @objc func screenDidLock() { screenLocked = true; report() }
    @objc func screenDidUnlock() { screenLocked = false; report() }
    @objc private func environmentChanged() { report() }

    private func installPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<MacPowerActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.report() }
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func currentPowerSource() -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return .unknown
        }
        switch type {
        case kIOPMACPowerKey, kIOPMUPSPowerKey: return .ac
        case kIOPMBatteryPowerKey: return .battery
        default: return .unknown
        }
    }

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
            screenObscured: screenAsleep || screenLocked,
            uiVisible: uiVisible,
            appBackgrounded: false, // a menu-bar agent is never "backgrounded" in the iOS sense
            powerSource: currentPowerSource(),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalTier: currentThermalTier()
        )
        guard inputs != lastReported else { return }
        lastReported = inputs
        onChange(inputs)
    }
}
#endif
