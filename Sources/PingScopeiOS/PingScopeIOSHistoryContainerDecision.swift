import PingScopeHistoryKit

public enum HistoryMapAuthorizationRequestDecision: Equatable, Sendable {
    case none
    case enableTagging
    case requestWhenInUse
    case openSettings
}

public struct HistoryMapPrerequisitePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let actionTitle: String?

    public init?(
        authorization: PingScopeIOSHistoryLocationAuthorization,
        taggingOptIn: Bool,
        locatedSampleCount: Int
    ) {
        switch (authorization, taggingOptIn, locatedSampleCount) {
        case (.denied, _, _):
            title = "Location access is off"
            detail = "Allow location access in Settings to tag future monitoring samples for the map."
            actionTitle = "Open Settings"
        case (.restricted, _, _):
            title = "Location access is restricted"
            detail = "This device does not currently allow location tagging, so the heat map is unavailable."
            actionTitle = nil
        case (.undetermined, _, _):
            title = "Map your connection history"
            detail = "Allow location access to tag future samples while monitoring."
            actionTitle = "Enable"
        case (.whenInUse, false, _), (.always, false, _):
            title = "Map your connection history"
            detail = "Enable location tagging for future samples while monitoring."
            actionTitle = "Enable"
        case (.whenInUse, true, 0), (.always, true, 0):
            title = "No location-tagged samples yet"
            detail = "Keep monitoring with Location Tagging enabled to add future samples. iCloud sync is optional and only adds samples that already include a location."
            actionTitle = nil
        case (.whenInUse, true, _), (.always, true, _):
            return nil
        }
    }
}

public struct HistoryMapAuthorizationPresentation: Equatable, Sendable {
    public let isMapAvailable: Bool
    public let showsContextualPrompt: Bool
    public let requestDecision: HistoryMapAuthorizationRequestDecision

    public init(
        authorization: PingScopeIOSHistoryLocationAuthorization,
        taggingOptIn: Bool
    ) {
        switch authorization {
        case .undetermined:
            isMapAvailable = false
            showsContextualPrompt = true
            requestDecision = .requestWhenInUse
        case .denied, .restricted:
            isMapAvailable = false
            showsContextualPrompt = true
            requestDecision = authorization == .denied ? .openSettings : .none
        case .whenInUse, .always:
            isMapAvailable = taggingOptIn
            showsContextualPrompt = !taggingOptIn
            requestDecision = taggingOptIn ? .none : .enableTagging
        }
    }

    public func effectiveLens(requested: HistoryLens) -> HistoryLens {
        requested == .map && !isMapAvailable ? .chart : requested
    }
}

public struct PingScopeIOSHistoryContainerDecision: Equatable, Sendable {
    public let selection: PingScopeIOSHistorySelection
    public let isMapAvailable: Bool
    public let effectiveLens: HistoryLens
    public let showsContextualPermissionPrompt: Bool
    public let permissionRequest: HistoryMapAuthorizationRequestDecision
    public let prerequisitePresentation: HistoryMapPrerequisitePresentation?
    public let resolvedPresentation: PingScopeIOSResolvedHistoryPresentation

    public init(
        requestedLens: HistoryLens,
        authorization: PingScopeIOSHistoryLocationAuthorization,
        taggingOptIn: Bool,
        selection: PingScopeIOSHistorySelection,
        presentationState: PingScopeIOSHistoryPresentationState
    ) {
        let authorizationPresentation = HistoryMapAuthorizationPresentation(
            authorization: authorization,
            taggingOptIn: taggingOptIn
        )
        self.selection = selection
        self.isMapAvailable = authorizationPresentation.isMapAvailable
        self.effectiveLens = authorizationPresentation.effectiveLens(requested: requestedLens)
        self.permissionRequest = authorizationPresentation.requestDecision
        let resolvedPresentation = PingScopeIOSHistoryPresentationResolver.resolve(
            presentationState,
            for: selection
        )
        let prerequisitePresentation = switch resolvedPresentation {
        case .loading:
            authorizationPresentation.showsContextualPrompt
                ? HistoryMapPrerequisitePresentation(
                    authorization: authorization,
                    taggingOptIn: taggingOptIn,
                    locatedSampleCount: 0
                )
                : nil
        case let .content(presentation):
            HistoryMapPrerequisitePresentation(
                authorization: authorization,
                taggingOptIn: taggingOptIn,
                locatedSampleCount: presentation.mapPresentation.locatedSampleCount
            )
        }
        // Empty authorized maps render their own in-map note. The top prompt is
        // reserved for an actionable authorization/tagging prerequisite so it
        // cannot cover the Chart lens or duplicate the map's empty state.
        self.showsContextualPermissionPrompt = authorizationPresentation.showsContextualPrompt
        self.prerequisitePresentation = prerequisitePresentation
        self.resolvedPresentation = resolvedPresentation
    }
}
