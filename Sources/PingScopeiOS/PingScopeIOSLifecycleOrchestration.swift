import Foundation

@MainActor
public final class PingScopeIOSLifecycleOperationQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let next = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = next
        return next
    }

    public func perform(_ operation: @escaping @MainActor () async -> Void) async {
        await enqueue(operation).value
    }

    public func waitForIdle() async {
        await tail?.value
    }
}

public struct PingScopeIOSActivityOwnershipLease: Equatable, Sendable {
    fileprivate let generation: UInt64
}

public actor PingScopeIOSActivityOwnership {
    private var generation: UInt64 = 0
    private var currentLease: PingScopeIOSActivityOwnershipLease?

    public init() {}

    public func claim() -> PingScopeIOSActivityOwnershipLease {
        generation &+= 1
        let lease = PingScopeIOSActivityOwnershipLease(generation: generation)
        currentLease = lease
        return lease
    }

    public func clear(ifCurrent lease: PingScopeIOSActivityOwnershipLease) -> Bool {
        guard currentLease == lease else { return false }
        currentLease = nil
        return true
    }

    public func isCurrent(_ lease: PingScopeIOSActivityOwnershipLease) -> Bool {
        currentLease == lease
    }
}

public enum PingScopeIOSLiveActivityAvailabilityDecision: Equatable, Sendable {
    case none
    case update
    case request

    public static func decide(
        isSessionActive: Bool,
        hasPlaceholderHost: Bool,
        hasActivity: Bool
    ) -> Self {
        guard isSessionActive else { return .none }
        if hasActivity { return .update }
        return hasPlaceholderHost ? .request : .none
    }
}
