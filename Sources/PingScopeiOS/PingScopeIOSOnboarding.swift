import Foundation
import PingScopeCore

public enum PingScopeIOSLocalNetworkCapability: Equatable, Sendable {
    case available
    case unavailable
    case notRequired

    public static func derive(hosts: [HostConfig], samples: [PingResult]) -> Self {
        let localHostIDs = Set(
            hosts
                .filter { $0.isEnabled && $0.requiresLocalNetworkPermission }
                .map(\.id)
        )
        guard !localHostIDs.isEmpty else { return .notRequired }
        let localSamples = samples.filter { localHostIDs.contains($0.hostID) }
        guard !localSamples.isEmpty else { return .notRequired }
        return localSamples.contains(where: \.isSuccess) ? .available : .unavailable
    }
}

public struct PingScopeIOSOnboardingInputs: Equatable, Sendable {
    public var notificationAuthorization: PingScopeIOSNotificationAuthorization
    public var localNetworkCapability: PingScopeIOSLocalNetworkCapability
    public var locationAuthorization: PingScopeIOSHistoryLocationAuthorization
    public var isLocationTaggingEnabled: Bool
    public var hasConfiguredWidget: Bool

    public init(
        notificationAuthorization: PingScopeIOSNotificationAuthorization,
        localNetworkCapability: PingScopeIOSLocalNetworkCapability,
        locationAuthorization: PingScopeIOSHistoryLocationAuthorization,
        isLocationTaggingEnabled: Bool,
        hasConfiguredWidget: Bool
    ) {
        self.notificationAuthorization = notificationAuthorization
        self.localNetworkCapability = localNetworkCapability
        self.locationAuthorization = locationAuthorization
        self.isLocationTaggingEnabled = isLocationTaggingEnabled
        self.hasConfiguredWidget = hasConfiguredWidget
    }
}

public struct PingScopeIOSOnboardingPresentation: Equatable, Sendable {
    public enum ItemID: String, CaseIterable, Equatable, Sendable {
        case notifications
        case localNetwork
        case location
        case widgets
    }

    public enum ItemStatus: Equatable, Sendable {
        case satisfied
        case needsAction
    }

    public enum Destination: Equatable, Sendable {
        case appSettings
        case widgetInstructions
    }

    public enum OverallStatus: Equatable, Sendable {
        case allSet
        case actionNeeded
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: ItemID
        public let title: String
        public let detail: String
        public let status: ItemStatus
        public let destination: Destination?
    }

    public let items: [Item]
    public let overallStatus: OverallStatus
    public let shouldPresentOnLaunch: Bool

    public init(inputs: PingScopeIOSOnboardingInputs, hasBeenSeen: Bool) {
        items = [
            Self.notificationsItem(inputs.notificationAuthorization),
            Self.localNetworkItem(inputs.localNetworkCapability),
            Self.locationItem(inputs),
            Self.widgetsItem(inputs.hasConfiguredWidget)
        ]
        overallStatus = items.allSatisfy { $0.status == .satisfied } ? .allSet : .actionNeeded
        shouldPresentOnLaunch = !hasBeenSeen && overallStatus == .actionNeeded
    }

    private static func notificationsItem(_ authorization: PingScopeIOSNotificationAuthorization) -> Item {
        let satisfied = authorization == .authorized || authorization == .provisional
        return Item(
            id: .notifications,
            title: "Notifications",
            detail: satisfied ? "Alerts are allowed" : "Review notification access in Settings",
            status: satisfied ? .satisfied : .needsAction,
            destination: satisfied ? nil : .appSettings
        )
    }

    private static func localNetworkItem(_ capability: PingScopeIOSLocalNetworkCapability) -> Item {
        switch capability {
        case .available:
            return Item(id: .localNetwork, title: "Local network", detail: "Local hosts are reachable", status: .satisfied, destination: nil)
        case .notRequired:
            return Item(id: .localNetwork, title: "Local network", detail: "Not needed by enabled hosts", status: .satisfied, destination: nil)
        case .unavailable:
            return Item(id: .localNetwork, title: "Local network", detail: "Review local network access in Settings", status: .needsAction, destination: .appSettings)
        }
    }

    private static func locationItem(_ inputs: PingScopeIOSOnboardingInputs) -> Item {
        let authorized = inputs.locationAuthorization == .whenInUse || inputs.locationAuthorization == .always
        let satisfied = inputs.isLocationTaggingEnabled && authorized
        return Item(
            id: .location,
            title: "Location",
            detail: satisfied ? "Map and Wi-Fi tagging are ready" : "Enable tagging and review location access",
            status: satisfied ? .satisfied : .needsAction,
            destination: satisfied ? nil : .appSettings
        )
    }

    private static func widgetsItem(_ configured: Bool) -> Item {
        Item(
            id: .widgets,
            title: "Widgets",
            detail: configured ? "A PingScope widget is configured" : "Add a PingScope widget from the Home Screen",
            status: configured ? .satisfied : .needsAction,
            destination: configured ? nil : .widgetInstructions
        )
    }
}

public final class PingScopeIOSOnboardingStore {
    private static let seenKey = "PingScopeIOS.onboarding.hasBeenSeen"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasBeenSeen: Bool {
        defaults.bool(forKey: Self.seenKey)
    }

    public func markSeen() {
        defaults.set(true, forKey: Self.seenKey)
    }
}
