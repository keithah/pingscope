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
    private var screenObscured = false
    private var uiVisible = true
    private var runLoopSource: CFRunLoopSource?
    private var lastReported: CadenceInputs?

    init(onChange: @escaping (CadenceInputs) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenAsleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenAwake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

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

    @objc private func screenAsleep() { screenObscured = true; report() }
    @objc private func screenAwake() { screenObscured = false; report() }
    @objc private func screenLocked() { screenObscured = true; report() }
    @objc private func screenUnlocked() { screenObscured = false; report() }
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
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any],
              let state = description[kIOPSPowerSourceStateKey] as? String else {
            return .unknown
        }
        return state == kIOPSACPowerValue ? .ac : .battery
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
            screenObscured: screenObscured,
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
