import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

enum StartOnLaunchService {
    static func isEnabled() -> Bool {
#if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
#endif
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
#if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
#if DEBUG
                print("[StartOnLaunch] Failed to set enabled=\(enabled): \(error)")
#endif
                return false
            }
        }
#endif
        return false
    }
}
