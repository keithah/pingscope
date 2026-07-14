import Foundation

public struct PingScopeIOSLiveActivityUpdatePolicy: Sendable {
    private let minimumUpdateInterval: TimeInterval
    private var lastPublishedState: PingScopeLiveActivityAttributes.ContentState?
    private var lastPublishedAt: Date?

    public init(minimumUpdateInterval: TimeInterval = 10) {
        self.minimumUpdateInterval = max(0, minimumUpdateInterval)
    }

    public mutating func shouldPublish(
        _ state: PingScopeLiveActivityAttributes.ContentState,
        at date: Date = Date()
    ) -> Bool {
        guard state != lastPublishedState else { return false }
        if let previous = lastPublishedState,
           let lastPublishedAt,
           !hasPriorityChange(from: previous, to: state),
           date.timeIntervalSince(lastPublishedAt) < minimumUpdateInterval {
            return false
        }
        lastPublishedState = state
        lastPublishedAt = date
        return true
    }

    public mutating func reset() {
        lastPublishedState = nil
        lastPublishedAt = nil
    }

    private func hasPriorityChange(
        from previous: PingScopeLiveActivityAttributes.ContentState,
        to next: PingScopeLiveActivityAttributes.ContentState
    ) -> Bool {
        guard previous.status == next.status,
              previous.isStale == next.isStale,
              previous.mode == next.mode else {
            return true
        }
        let previousRows = previous.hostRows.map { ($0.hostID, $0.status, $0.isStale) }
        let nextRows = next.hostRows.map { ($0.hostID, $0.status, $0.isStale) }
        guard previousRows.count == nextRows.count else { return true }
        return zip(previousRows, nextRows).contains { previousRow, nextRow in
            previousRow.0 != nextRow.0
                || previousRow.1 != nextRow.1
                || previousRow.2 != nextRow.2
        }
    }
}

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

@MainActor
public protocol PingScopeIOSLiveActivityDirectory {
    associatedtype ActivityHandle

    var currentActivities: [ActivityHandle] { get }
    func end(_ activity: ActivityHandle) async
}

@MainActor
public enum PingScopeIOSLiveActivityStartup {
    public static func requestReplacingOrphans<Directory, RequestedActivity>(
        in directory: Directory,
        request: () async throws -> RequestedActivity
    ) async rethrows -> RequestedActivity where Directory: PingScopeIOSLiveActivityDirectory {
        for orphan in directory.currentActivities {
            await directory.end(orphan)
        }
        return try await request()
    }
}

public struct PingScopeIOSLifecycleSessionIdentity: Equatable, Sendable {
    public let token: UUID
    public let scope: PingScopeIOSHostScope
    public let focusedHostID: UUID?
    public let startedAt: Date

    public init(
        token: UUID = UUID(),
        scope: PingScopeIOSHostScope,
        focusedHostID: UUID?,
        startedAt: Date
    ) {
        self.token = token
        self.scope = scope
        self.focusedHostID = focusedHostID
        self.startedAt = startedAt
    }

    public func describes(
        scope: PingScopeIOSHostScope,
        focusedHostID: UUID?,
        startedAt: Date
    ) -> Bool {
        self.scope == scope && self.focusedHostID == focusedHostID && self.startedAt == startedAt
    }
}

public enum PingScopeIOSCoordinatorSessionState: Equatable, Sendable {
    case idle
    case active
    case ended
}

public enum PingScopeIOSLifecycleScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

public struct PingScopeIOSLifecycleSceneEpoch: Equatable, Sendable {
    fileprivate let generation: UInt64
    public let phase: PingScopeIOSLifecycleScenePhase
}

@MainActor
public protocol PingScopeIOSPromptBackgroundProtectionClient: AnyObject {
    func beginPromptBackgroundProtection()
    func endPromptBackgroundProtection()
}

/// ActivityKit-free lifecycle state used by the app model and focused tests.
/// External callbacks capture identities synchronously, then revalidate them
/// after entering the FIFO before they are allowed to mutate session state.
@MainActor
public final class PingScopeIOSLifecycleHarness {
    private let operations = PingScopeIOSLifecycleOperationQueue()
    private let activityOwnership = PingScopeIOSActivityOwnership()
    private let promptBackgroundProtectionClient: (any PingScopeIOSPromptBackgroundProtectionClient)?
    private var promptBackgroundProtectionIsActive = false
    private var sceneGeneration: UInt64 = 0
    private var refreshedSessionIdentity: PingScopeIOSLifecycleSessionIdentity?
    private var coordinatorState: PingScopeIOSCoordinatorSessionState = .idle

    public private(set) var currentSessionIdentity: PingScopeIOSLifecycleSessionIdentity?
    public private(set) var currentSceneEpoch = PingScopeIOSLifecycleSceneEpoch(
        generation: 0,
        phase: .inactive
    )

    public init(promptBackgroundProtectionClient: (any PingScopeIOSPromptBackgroundProtectionClient)? = nil) {
        self.promptBackgroundProtectionClient = promptBackgroundProtectionClient
    }

    @discardableResult
    public func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        operations.enqueue(operation)
    }

    public func waitForIdle() async {
        await operations.waitForIdle()
    }

    public func recordRefresh(
        sessionIdentity: PingScopeIOSLifecycleSessionIdentity?,
        coordinatorState: PingScopeIOSCoordinatorSessionState
    ) {
        currentSessionIdentity = sessionIdentity
        refreshedSessionIdentity = sessionIdentity
        self.coordinatorState = coordinatorState
    }

    @discardableResult
    public func enqueueFiniteCompletion(
        for sessionIdentity: PingScopeIOSLifecycleSessionIdentity,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        enqueue { [weak self] in
            guard let self,
                  self.currentSessionIdentity == sessionIdentity,
                  self.refreshedSessionIdentity == sessionIdentity,
                  self.coordinatorState == .ended else {
                return
            }
            await operation()
        }
    }

    @discardableResult
    public func transitionScene(to phase: PingScopeIOSLifecycleScenePhase) -> PingScopeIOSLifecycleSceneEpoch {
        sceneGeneration &+= 1
        let epoch = PingScopeIOSLifecycleSceneEpoch(generation: sceneGeneration, phase: phase)
        currentSceneEpoch = epoch
        if phase == .background {
            beginPromptBackgroundProtection()
        } else {
            endPromptBackgroundProtection()
        }
        return epoch
    }

    public func isCurrentBackground(_ epoch: PingScopeIOSLifecycleSceneEpoch) -> Bool {
        currentSceneEpoch == epoch && currentSceneEpoch.phase == .background
    }

    @discardableResult
    public func enqueueBackgroundWork(
        originatingAt epoch: PingScopeIOSLifecycleSceneEpoch,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        enqueue { [weak self] in
            guard let self, self.isCurrentBackground(epoch) else { return }
            await operation()
        }
    }

    @discardableResult
    public func enqueueBackgroundExpiration(
        originatingAt epoch: PingScopeIOSLifecycleSceneEpoch,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        enqueueBackgroundWork(originatingAt: epoch, operation: operation)
    }

    public func finishPromptBackgroundProtection() {
        endPromptBackgroundProtection()
    }

    public func claimActivity() async -> PingScopeIOSActivityOwnershipLease {
        await activityOwnership.claim()
    }

    public func clearActivity(ifCurrent lease: PingScopeIOSActivityOwnershipLease) async -> Bool {
        await activityOwnership.clear(ifCurrent: lease)
    }

    public func isActivityCurrent(_ lease: PingScopeIOSActivityOwnershipLease) async -> Bool {
        await activityOwnership.isCurrent(lease)
    }

    private func beginPromptBackgroundProtection() {
        guard !promptBackgroundProtectionIsActive else { return }
        promptBackgroundProtectionIsActive = true
        promptBackgroundProtectionClient?.beginPromptBackgroundProtection()
    }

    private func endPromptBackgroundProtection() {
        guard promptBackgroundProtectionIsActive else { return }
        promptBackgroundProtectionIsActive = false
        promptBackgroundProtectionClient?.endPromptBackgroundProtection()
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
