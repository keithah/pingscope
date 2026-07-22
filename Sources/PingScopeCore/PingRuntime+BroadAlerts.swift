import Foundation

enum BroadOutageAggregateCandidate: Equatable {
    case internetLoss([PingResult])
    case pathRecovered
}

struct BroadOutageAlertCoordinator {
    private var aggregateInternetOutageActive = false
    private var pathAlertActive = false
    private var recoverySuppressionHostIDs: Set<UUID> = []

    var isPathAlertActive: Bool {
        pathAlertActive
    }

    mutating func aggregateCandidate(
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth],
        rules: NotificationRuleSet
    ) -> BroadOutageAggregateCandidate? {
        let alertableHostIDs = Self.alertableHostIDs(hosts)
        guard rules.isEnabled, alertableHostIDs.count > 1 else {
            aggregateInternetOutageActive = false
            return nil
        }

        let latestResults = healthByHost.values
            .filter { alertableHostIDs.contains($0.hostID) }
            .compactMap(\.latestResult)
        guard latestResults.count == alertableHostIDs.count else { return nil }

        let failedHostIDs = Set(latestResults.filter { !$0.isSuccess }.map(\.hostID))
        let failureRatio = Double(failedHostIDs.count) / Double(latestResults.count)
        let isOutage = failureRatio >= rules.internetLossFailureRatio

        if isOutage {
            guard !aggregateInternetOutageActive, !pathAlertActive else { return nil }
            // Detection owns host-transition suppression even when the broad
            // notification is inside its cooldown. Keep disabled alert types
            // independent so users who opt out of internet-loss alerts still
            // receive the enabled per-host transitions.
            if rules.alertTypes.contains(.internetLoss) {
                aggregateInternetOutageActive = true
                recoverySuppressionHostIDs.formUnion(
                    Self.currentFailingAlertableHostIDs(hosts: hosts, healthByHost: healthByHost)
                )
            }
            return .internetLoss(latestResults)
        }

        if aggregateInternetOutageActive, failedHostIDs.isEmpty {
            aggregateInternetOutageActive = false
            if pathAlertActive, shouldDeliverPathRecovered(rules: rules) {
                return .pathRecovered
            }
        }
        return nil
    }

    mutating func pathRecoveredAlertIfNeeded(rules: NotificationRuleSet) -> AlertDecision? {
        guard pathAlertActive, shouldDeliverPathRecovered(rules: rules) else { return nil }
        pathAlertActive = false
        return .pathRecovered
    }

    mutating func recordDelivered(
        _ decision: AlertDecision,
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth]
    ) {
        switch decision {
        case .internetLoss, .localNetworkDown, .ispPathDown, .upstreamDown, .pathDegraded:
            if decision == .internetLoss {
                aggregateInternetOutageActive = true
            }
            pathAlertActive = true
            recoverySuppressionHostIDs.formUnion(Self.currentFailingAlertableHostIDs(hosts: hosts, healthByHost: healthByHost))
        case .pathRecovered:
            aggregateInternetOutageActive = false
            pathAlertActive = false
        default:
            break
        }
    }

    mutating func shouldSuppressTransition(
        _ decision: AlertDecision,
        diagnosisAlert: AlertDecision?,
        aggregateAlert: AlertDecision?
    ) -> Bool {
        switch decision {
        case let .hostDown(hostID):
            if aggregateInternetOutageActive || pathAlertActive || aggregateAlert != nil || diagnosisAlert != nil {
                recoverySuppressionHostIDs.insert(hostID)
                return true
            }
            return false
        case let .recovered(hostID):
            if recoverySuppressionHostIDs.remove(hostID) != nil {
                return true
            }
            if aggregateAlert == .pathRecovered || pathAlertActive {
                return true
            }
            return false
        default:
            return false
        }
    }

    mutating func reset() {
        aggregateInternetOutageActive = false
        pathAlertActive = false
        recoverySuppressionHostIDs.removeAll()
    }

    private func shouldDeliverPathRecovered(rules: NotificationRuleSet) -> Bool {
        rules.isEnabled
            && rules.notifyOnRecovery
            && rules.alertTypes.contains(.recovered)
    }

    private static func currentFailingAlertableHostIDs(
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth]
    ) -> Set<UUID> {
        let alertableHostIDs = alertableHostIDs(hosts)
        return Set(healthByHost.values.compactMap { health in
            guard alertableHostIDs.contains(health.hostID),
                  health.latestResult?.isSuccess == false else {
                return nil
            }
            return health.hostID
        })
    }

    private static func alertableHostIDs(_ hosts: [HostConfig]) -> Set<UUID> {
        Set(hosts.filter { $0.isEnabled && $0.notifications != .muted }.map(\.id))
    }
}
