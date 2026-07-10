public struct PingScopeIOSInitialSessionCoordinator: Sendable {
    private var hasStartedInitialSession = false

    public init() {}

    public var shouldStartInitialSession: Bool {
        !hasStartedInitialSession
    }

    public mutating func markInitialSessionStarted() {
        hasStartedInitialSession = true
    }

    public mutating func markExplicitSessionAction() {
        hasStartedInitialSession = true
    }
}
