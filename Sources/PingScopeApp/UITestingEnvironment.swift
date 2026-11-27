import Foundation
import PingScopeCore

/// Isolation for XCUITest runs (`PingScopeUITests`).
///
/// UI tests launch the real app bundle, which shares `com.hadm.PingScope` with
/// the developer's installed copy. Without isolation a test run would read and
/// rewrite the developer's hosts and settings, append to their history
/// database, push test hosts to their iCloud account, and lose the
/// single-instance lock to an already-running PingScope.
///
/// The mode is active only in DEBUG builds launched with
/// `PINGSCOPE_UI_TESTING=1` in the environment, which `XCUIApplication`
/// sets through `launchEnvironment`. Release and App Store builds ignore it.
enum UITestingEnvironment {
    static let environmentKey = "PINGSCOPE_UI_TESTING"
    static let defaultsSuiteName = "com.hadm.PingScope.uitests"

    static let isActive: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment[environmentKey] == "1"
        #else
        false
        #endif
    }()

    /// The defaults every app-side read and write goes through. A UI-test
    /// launch gets a suite that is wiped at launch, so each test starts from
    /// first-run state.
    ///
    /// `nonisolated(unsafe)`: `UserDefaults` is documented thread-safe but not
    /// marked `Sendable`, and it replaces `UserDefaults.standard`, which call
    /// sites already use from any isolation.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isActive, let suite = UserDefaults(suiteName: defaultsSuiteName) else {
            return .standard
        }
        suite.removePersistentDomain(forName: defaultsSuiteName)
        return suite
    }()

    /// A history database in the temporary directory, emptied at launch, so
    /// tests never read or append to the developer's real history. One
    /// UI-test instance runs at a time (its own single-instance lock), so a
    /// fixed directory is safe to wipe.
    static func historyDatabaseURL() throws -> URL {
        guard isActive else { return try SQLiteHistoryStore.defaultURL() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PingScope-UITests", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("History.sqlite")
    }

    /// UI-test launches take their own lock so they run beside an installed,
    /// running PingScope instead of terminating at launch.
    static var singleInstanceLockName: String {
        isActive ? "com.pingscope.fresh.uitests.lock" : "com.pingscope.fresh.lock"
    }
}
