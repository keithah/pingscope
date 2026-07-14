import Foundation
import PingScopeCore

public struct PingScopeIOSHistoryLocationSnapshot: Equatable, Sendable {
    public var isTaggingEnabled: Bool
    public var isAuthorized: Bool
    public var fix: SampleLocation?
    public var networkInterface: String?
    public var networkName: String?
    public var isVPN: Bool

    public init(
        isTaggingEnabled: Bool = false,
        isAuthorized: Bool = false,
        fix: SampleLocation? = nil,
        networkInterface: String? = nil,
        networkName: String? = nil,
        isVPN: Bool = false
    ) {
        self.isTaggingEnabled = isTaggingEnabled
        self.isAuthorized = isAuthorized
        self.fix = fix
        self.networkInterface = networkInterface
        self.networkName = networkName
        self.isVPN = isVPN
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

    public func updateNetwork(interface: String?, name: String?, isVPN: Bool) {
        lock.withLock {
            value.networkInterface = interface
            value.networkName = name
            value.isVPN = isVPN
        }
    }

    public func updateNetworkName(_ name: String, ifInterfaceMatches interface: String) {
        let normalized = NetworkInterfaceNormalizer.normalize(interface)
        lock.withLock {
            guard NetworkInterfaceNormalizer.normalize(value.networkInterface) == normalized else { return }
            value.networkName = name
        }
    }

    public func makeHistorySampleEnricher() -> PingScopeIOSHistorySampleEnricher {
        { [self] result in
            let current = snapshot()
            // Network label is captured on EVERY sample, independent of location
            // tagging/authorization. Name falls back to the interface's display
            // name when the platform did not supply an explicit name (e.g. SSID).
            let normalizedInterface = NetworkInterfaceNormalizer.normalize(current.networkInterface)
            let resolvedName = current.networkName ?? normalizedInterface.map(NetworkInterfaceNormalizer.displayName(for:))

            var enriched = result
            enriched.networkInterface = normalizedInterface
            enriched.networkName = resolvedName
            enriched.isVPN = current.isVPN

            // A coordinate is only attached when tagging is enabled, authorized,
            // and a fix is available; otherwise only the network label is stamped.
            if current.isTaggingEnabled,
               current.isAuthorized,
               let fix = current.fix,
               let location = SampleLocation(
                   latitude: fix.latitude,
                   longitude: fix.longitude,
                   horizontalAccuracy: fix.horizontalAccuracy,
                   networkName: resolvedName,
                   networkInterface: normalizedInterface
               ) {
                enriched.location = location
            }
            return enriched
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
