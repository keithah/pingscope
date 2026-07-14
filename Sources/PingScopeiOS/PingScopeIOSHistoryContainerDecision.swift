import PingScopeHistoryKit

public enum HistoryMapAuthorizationRequestDecision: Equatable, Sendable {
    case none
    case enableTagging
    case requestWhenInUse
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
            showsContextualPrompt = false
            requestDecision = .none
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
        self.showsContextualPermissionPrompt = authorizationPresentation.showsContextualPrompt
        self.permissionRequest = authorizationPresentation.requestDecision
        self.resolvedPresentation = PingScopeIOSHistoryPresentationResolver.resolve(
            presentationState,
            for: selection
        )
    }
}
