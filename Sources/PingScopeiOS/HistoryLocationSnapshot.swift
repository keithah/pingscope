import Foundation
import PingScopeCore

public struct PingScopeIOSHistoryLocationSnapshot: Equatable, Sendable {
    public var isTaggingEnabled: Bool
    public var isAuthorized: Bool
    public var fix: SampleLocation?
    public var networkInterface: String?

    public init(
        isTaggingEnabled: Bool = false,
        isAuthorized: Bool = false,
        fix: SampleLocation? = nil,
        networkInterface: String? = nil
    ) {
        self.isTaggingEnabled = isTaggingEnabled
        self.isAuthorized = isAuthorized
        self.fix = fix
        self.networkInterface = networkInterface
    }
}

public final class PingScopeIOSHistoryLocationSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PingScopeIOSHistoryLocationSnapshot

    public init(snapshot: PingScopeIOSHistoryLocationSnapshot = .init()) {
        value = snapshot
    }

    public func snapshot() -> PingScopeIOSHistoryLocationSnapshot {
        lock.withLock { value }
    }

    public func update(_ snapshot: PingScopeIOSHistoryLocationSnapshot) {
        lock.withLock { value = snapshot }
    }

    public func updateTagging(enabled: Bool, authorized: Bool) {
        lock.withLock {
            value.isTaggingEnabled = enabled
            value.isAuthorized = authorized
        }
    }

    public func updateFix(_ fix: SampleLocation?) {
        lock.withLock { value.fix = fix }
    }

    public func updateNetworkInterface(_ interface: String?) {
        lock.withLock { value.networkInterface = interface }
    }

    public func makeHistorySampleEnricher() -> PingScopeIOSHistorySampleEnricher {
        { [self] result in
            let current = snapshot()
            guard current.isTaggingEnabled,
                  current.isAuthorized,
                  let fix = current.fix else { return result }
            let normalizedInterface = Self.normalizedInterface(current.networkInterface)
            guard
                  let location = SampleLocation(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    horizontalAccuracy: fix.horizontalAccuracy,
                    networkName: normalizedInterface.map(Self.displayName(for:)),
                    networkInterface: normalizedInterface
                  ) else { return result }
            var enriched = result
            enriched.location = location
            return enriched
        }
    }

    private static func normalizedInterface(_ value: String?) -> String? {
        guard let value else { return nil }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wifi": "wifi"
        case "cellular": "cellular"
        case "wired": "wired"
        default: "other"
        }
    }

    private static func displayName(for interface: String) -> String {
        switch interface {
        case "wifi": "Wi-Fi"
        case "cellular": "Cellular"
        case "wired": "Wired"
        default: "Other"
        }
    }
}

public struct PingScopeIOSHistoryLocationFixCandidate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double?

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}

public enum PingScopeIOSHistoryLocationFixReducer {
    public static func latestValidFix(
        from candidates: [PingScopeIOSHistoryLocationFixCandidate],
        preserving previous: SampleLocation?
    ) -> SampleLocation? {
        for candidate in candidates.reversed() {
            if let fix = SampleLocation(
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                horizontalAccuracy: candidate.horizontalAccuracy
            ) {
                return fix
            }
        }
        return previous
    }
}

public enum PingScopeIOSHistoryLocationAuthorization: Equatable, Sendable {
    case undetermined
    case denied
    case restricted
    case whenInUse
    case always
}

public enum PingScopeIOSHistoryLocationAccuracy: Equatable, Sendable {
    case keepAlive
    case tagging
}

public struct PingScopeIOSHistoryLocationPolicy: Equatable, Sendable {
    public var updatesActive: Bool
    public var backgroundActive: Bool
    public var accuracy: PingScopeIOSHistoryLocationAccuracy?

    public init(
        updatesActive: Bool,
        backgroundActive: Bool,
        accuracy: PingScopeIOSHistoryLocationAccuracy?
    ) {
        self.updatesActive = updatesActive
        self.backgroundActive = backgroundActive
        self.accuracy = accuracy
    }

    public static let inactive = Self(updatesActive: false, backgroundActive: false, accuracy: nil)

    public static func reduce(
        keepAliveEnabled: Bool,
        taggingEnabled: Bool,
        monitoringActive: Bool,
        authorization: PingScopeIOSHistoryLocationAuthorization
    ) -> Self {
        guard monitoringActive else { return .inactive }
        let keepAliveActive = keepAliveEnabled && authorization == .always
        let taggingActive = taggingEnabled && (authorization == .whenInUse || authorization == .always)
        guard keepAliveActive || taggingActive else { return .inactive }
        return Self(
            updatesActive: true,
            backgroundActive: keepAliveActive,
            accuracy: taggingActive ? .tagging : .keepAlive
        )
    }
}

public enum PingScopeIOSHistoryLocationEvent: Equatable, Sendable {
    case setState(keepAliveEnabled: Bool, taggingEnabled: Bool, monitoringActive: Bool)
    case requestTaggingAuthorization
    case requestKeepAliveAuthorization
    case authorizationChanged(PingScopeIOSHistoryLocationAuthorization)
}

public enum PingScopeIOSHistoryLocationCommand: Equatable, Sendable {
    case requestWhenInUseAuthorization
    case requestAlwaysAuthorization
    case configureAccuracy(PingScopeIOSHistoryLocationAccuracy)
    case setBackgroundUpdates(Bool)
    case startUpdatingLocation
    case stopUpdatingLocation
}

public struct PingScopeIOSHistoryLocationStateMachine: Sendable {
    public private(set) var authorization: PingScopeIOSHistoryLocationAuthorization
    public private(set) var policy: PingScopeIOSHistoryLocationPolicy = .inactive
    private var keepAliveEnabled = false
    private var taggingEnabled = false
    private var monitoringActive = false
    private var pendingAlwaysEscalation = false

    public init(authorization: PingScopeIOSHistoryLocationAuthorization) {
        self.authorization = authorization
    }

    public mutating func handle(
        _ event: PingScopeIOSHistoryLocationEvent
    ) -> [PingScopeIOSHistoryLocationCommand] {
        var authorizationCommands: [PingScopeIOSHistoryLocationCommand] = []
        switch event {
        case let .setState(keepAliveEnabled, taggingEnabled, monitoringActive):
            self.keepAliveEnabled = keepAliveEnabled
            self.taggingEnabled = taggingEnabled
            self.monitoringActive = monitoringActive
            if !keepAliveEnabled {
                pendingAlwaysEscalation = false
            }
        case .requestTaggingAuthorization:
            if authorization == .undetermined {
                authorizationCommands.append(.requestWhenInUseAuthorization)
            }
        case .requestKeepAliveAuthorization:
            switch authorization {
            case .undetermined:
                pendingAlwaysEscalation = true
                authorizationCommands.append(.requestWhenInUseAuthorization)
            case .whenInUse:
                pendingAlwaysEscalation = false
                authorizationCommands.append(.requestAlwaysAuthorization)
            case .denied, .restricted, .always:
                pendingAlwaysEscalation = false
            }
        case let .authorizationChanged(authorization):
            self.authorization = authorization
            if pendingAlwaysEscalation, authorization == .whenInUse {
                pendingAlwaysEscalation = false
                authorizationCommands.append(.requestAlwaysAuthorization)
            } else if authorization != .undetermined {
                pendingAlwaysEscalation = false
            }
        }

        let nextPolicy = PingScopeIOSHistoryLocationPolicy.reduce(
            keepAliveEnabled: keepAliveEnabled,
            taggingEnabled: taggingEnabled,
            monitoringActive: monitoringActive,
            authorization: authorization
        )
        let transitionCommands = commands(from: policy, to: nextPolicy)
        policy = nextPolicy
        return authorizationCommands + transitionCommands
    }

    private func commands(
        from previous: PingScopeIOSHistoryLocationPolicy,
        to next: PingScopeIOSHistoryLocationPolicy
    ) -> [PingScopeIOSHistoryLocationCommand] {
        guard previous != next else { return [] }
        var commands: [PingScopeIOSHistoryLocationCommand] = []
        if next.updatesActive, next.accuracy != previous.accuracy, let accuracy = next.accuracy {
            commands.append(.configureAccuracy(accuracy))
        }
        if next.backgroundActive != previous.backgroundActive {
            commands.append(.setBackgroundUpdates(next.backgroundActive))
        }
        if next.updatesActive != previous.updatesActive {
            commands.append(next.updatesActive ? .startUpdatingLocation : .stopUpdatingLocation)
        }
        return commands
    }
}
