import Foundation

public struct NetworkPerspectiveDiagnosis: Equatable, Sendable {
    public enum Scope: String, Codable, Equatable, Sendable {
        case noData
        case allReachable
        case localNetwork
        case upstream
        case remoteService
        case partialDegradation
    }

    public enum Confidence: String, Codable, Equatable, Sendable {
        case high
        case tentative

        public var displayName: String {
            switch self {
            case .high: "High confidence"
            case .tentative: "Tentative"
            }
        }
    }

    public enum Verdict: Equatable, Sendable {
        case noData
        case allReachable
        case localNetworkDown
        case ispPathDown
        case upstreamDown
        case remoteServiceDown(hostIDs: [UUID])
        case partialDegradation(tier: NetworkTier)
        case multipleFailures(hostIDs: [UUID])
    }

    public struct TierEvidence: Equatable, Sendable {
        public var tier: NetworkTier
        public var totalCount: Int
        public var healthyCount: Int
        public var degradedCount: Int
        public var downCount: Int

        public init(
            tier: NetworkTier,
            totalCount: Int,
            healthyCount: Int,
            degradedCount: Int,
            downCount: Int
        ) {
            self.tier = tier
            self.totalCount = totalCount
            self.healthyCount = healthyCount
            self.degradedCount = degradedCount
            self.downCount = downCount
        }

        public var status: HealthStatus {
            if downCount > 0 { return .down }
            if degradedCount > 0 { return .degraded }
            if healthyCount > 0 { return .healthy }
            return .noData
        }

        public var summary: String {
            "\(healthyCount) ok, \(degradedCount) slow, \(downCount) down"
        }
    }

    public var scope: Scope
    public var title: String
    public var detail: String
    public var affectedHostIDs: [UUID]
    public var verdict: Verdict
    public var confidence: Confidence
    public var faultTier: NetworkTier?
    public var evidenceNote: String?
    public var tierEvidence: [TierEvidence]

    public init(
        scope: Scope,
        title: String,
        detail: String,
        affectedHostIDs: [UUID] = [],
        verdict: Verdict? = nil,
        confidence: Confidence = .high,
        faultTier: NetworkTier? = nil,
        evidenceNote: String? = nil,
        tierEvidence: [TierEvidence] = []
    ) {
        self.scope = scope
        self.title = title
        self.detail = detail
        self.affectedHostIDs = affectedHostIDs
        self.verdict = verdict ?? Self.defaultVerdict(scope: scope, affectedHostIDs: affectedHostIDs)
        self.confidence = confidence
        self.faultTier = faultTier
        self.evidenceNote = evidenceNote
        self.tierEvidence = tierEvidence
    }

    private static func defaultVerdict(scope: Scope, affectedHostIDs: [UUID]) -> Verdict {
        switch scope {
        case .noData: .noData
        case .allReachable: .allReachable
        case .localNetwork: .localNetworkDown
        case .upstream: .upstreamDown
        case .remoteService: .remoteServiceDown(hostIDs: affectedHostIDs)
        case .partialDegradation: .multipleFailures(hostIDs: affectedHostIDs)
        }
    }
}

public struct NetworkPerspectiveDiagnoser: Sendable {
    private struct ObservedHost {
        var host: HostConfig
        var health: HostHealth
        var tier: NetworkTier
    }

    private struct TierSummary {
        var tier: NetworkTier
        var observed: [ObservedHost]
        var down: [ObservedHost]
        var degraded: [ObservedHost]
        var healthy: [ObservedHost]
        var downRatio: Double
        var degradedRatio: Double

        init(tier: NetworkTier, observed: [ObservedHost]) {
            self.tier = tier
            self.observed = observed
            var down: [ObservedHost] = []
            var degraded: [ObservedHost] = []
            var healthy: [ObservedHost] = []
            down.reserveCapacity(observed.count)
            degraded.reserveCapacity(observed.count)
            healthy.reserveCapacity(observed.count)
            for host in observed {
                switch host.health.status {
                case .down:
                    down.append(host)
                case .degraded:
                    degraded.append(host)
                case .healthy:
                    healthy.append(host)
                case .noData:
                    continue
                }
            }
            self.down = down
            self.degraded = degraded
            self.healthy = healthy
            self.downRatio = observed.isEmpty ? 0 : Double(down.count) / Double(observed.count)
            self.degradedRatio = observed.isEmpty ? 0 : Double(degraded.count) / Double(observed.count)
        }

        var hasDown: Bool {
            !down.isEmpty
        }

        var hasDegraded: Bool {
            !degraded.isEmpty
        }
    }

    private let classifier: NetworkTierClassifier

    public init(classifier: NetworkTierClassifier = NetworkTierClassifier()) {
        self.classifier = classifier
    }

    public func diagnose(
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth],
        networkStatus: NetworkConnectivityStatus = .connected
    ) -> NetworkPerspectiveDiagnosis {
        let enabledHosts = hosts.filter(\.isEnabled)
        guard !enabledHosts.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No hosts enabled",
                detail: "Enable at least one host to diagnose network scope.",
                confidence: .tentative
            )
        }

        if let gatedDiagnosis = linkStateDiagnosis(for: networkStatus) {
            return gatedDiagnosis
        }

        let activeInterface = enabledHosts.compactMap { host -> PingResult? in
            guard let result = healthByHost[host.id]?.latestResult,
                  result.networkInterface != nil else { return nil }
            return result
        }.max { $0.timestamp < $1.timestamp }?.networkInterface
        let diagnosticHosts = enabledHosts.filter { host in
            !(activeInterface == "cellular" && classifier.tier(for: host) == .localGateway)
        }

        let observed = diagnosticHosts.compactMap { host -> ObservedHost? in
            guard let health = healthByHost[host.id], health.latestResult != nil else { return nil }
            return ObservedHost(host: host, health: health, tier: classifier.tier(for: host))
        }
        guard !observed.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No recent measurements",
                detail: "PingScope needs samples before it can infer what is down.",
                confidence: .tentative
            )
        }

        let observedByTier = Dictionary(grouping: observed, by: \.tier)
        let summaries = NetworkTier.allCases
            .sorted { $0.depth < $1.depth }
            .compactMap { tier -> TierSummary? in
                guard let tierObserved = observedByTier[tier], !tierObserved.isEmpty else { return nil }
                return TierSummary(tier: tier, observed: tierObserved)
            }
        let tierEvidence = evidenceChain(from: summaries)

        let downSummaries = summaries.filter(\.hasDown)
        if downSummaries.isEmpty {
            let degradedSummaries = summaries.filter(\.hasDegraded)
            if degradedSummaries.isEmpty {
                let healthyCount = observed.reduce(0) { count, host in
                    count + (host.health.status == .healthy ? 1 : 0)
                }
                return NetworkPerspectiveDiagnosis(
                    scope: .allReachable,
                    title: "Everything reachable",
                    detail: "\(healthyCount) monitored host\(healthyCount == 1 ? "" : "s") responding.",
                    verdict: .allReachable,
                    confidence: .high,
                    evidenceNote: "\(healthyCount)/\(observed.count) monitored hosts healthy",
                    tierEvidence: tierEvidence
                )
            }
            let summary = degradedSummaries.min { $0.tier.depth < $1.tier.depth }!
            return NetworkPerspectiveDiagnosis(
                scope: .partialDegradation,
                title: "\(summary.tier.displayName) degraded",
                detail: names(summary.degraded) + " above threshold.",
                affectedHostIDs: summary.degraded.map(\.host.id),
                verdict: .partialDegradation(tier: summary.tier),
                confidence: confidence(for: summary, innerSummaries: innerSummaries(before: summary.tier, in: summaries)),
                faultTier: summary.tier,
                evidenceNote: evidence(for: summary, status: "degraded"),
                tierEvidence: tierEvidence
            )
        }

        let fault = downSummaries.min { $0.tier.depth < $1.tier.depth }!
        let affected = fault.down.map(\.host.id)
        let confidence = confidence(for: fault, innerSummaries: innerSummaries(before: fault.tier, in: summaries))
        let evidence = evidence(for: fault, status: "down")

        switch fault.tier {
        case .localGateway:
            let title = fault.down.contains { $0.host.displayName.localizedCaseInsensitiveContains("gateway") } ? "Default gateway down" : "Local network down"
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: title,
                detail: "\(names(fault.down)) not responding; failures beyond the router are unknown.",
                affectedHostIDs: affected,
                verdict: .localNetworkDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .ispEdge:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "ISP path down",
                detail: "The router responds, but the modem, dish, or ISP edge is not reachable.",
                affectedHostIDs: affected,
                verdict: .ispPathDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .upstream:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "Upstream path down",
                detail: "Router and ISP checks respond, but internet checks are not reachable.",
                affectedHostIDs: affected,
                verdict: .upstreamDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .remoteService:
            return NetworkPerspectiveDiagnosis(
                scope: .remoteService,
                title: affected.count == 1 ? "Remote host down" : "Remote services down",
                detail: names(fault.down) + " not responding while inner tiers are reachable.",
                affectedHostIDs: affected,
                verdict: .remoteServiceDown(hostIDs: affected),
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        }
    }

    private func innerSummaries(before tier: NetworkTier, in summaries: [TierSummary]) -> [TierSummary] {
        summaries.filter { $0.tier.depth < tier.depth }
    }

    private func linkStateDiagnosis(for status: NetworkConnectivityStatus) -> NetworkPerspectiveDiagnosis? {
        switch status {
        case .connected:
            return nil
        case .notConnected:
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: "Network disconnected",
                detail: "macOS reports no active network link, so PingScope is not blaming ISP or remote hosts.",
                verdict: .localNetworkDown,
                confidence: .high,
                faultTier: .localGateway,
                evidenceNote: status.displayName
            )
        case .noIPAddress:
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: "No IP address",
                detail: "The local interface has no usable IP address; upstream diagnosis is suppressed.",
                verdict: .localNetworkDown,
                confidence: .high,
                faultTier: .localGateway,
                evidenceNote: status.displayName
            )
        case .noInternet:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "No internet connection",
                detail: "macOS reports no internet route; PingScope will wait for connectivity before naming a host-specific failure.",
                verdict: .upstreamDown,
                confidence: .tentative,
                faultTier: .upstream,
                evidenceNote: status.displayName
            )
        }
    }

    private func confidence(for summary: TierSummary, innerSummaries: [TierSummary]) -> NetworkPerspectiveDiagnosis.Confidence {
        let boundaryIsClean = innerSummaries.allSatisfy { !$0.hasDown }
        guard boundaryIsClean else { return .tentative }
        if summary.observed.count == 1 {
            return summary.down.first?.health.consecutiveFailureCount ?? 0 > 1 || summary.downRatio >= 1 ? .high : .tentative
        }
        return summary.downRatio >= 0.75 || summary.degradedRatio >= 0.75 ? .high : .tentative
    }

    private func evidence(for summary: TierSummary, status: String) -> String {
        let matchingCount = status == "degraded" ? summary.degraded.count : summary.down.count
        return "\(matchingCount)/\(summary.observed.count) \(summary.tier.displayName.lowercased()) host\(summary.observed.count == 1 ? "" : "s") \(status)"
    }

    private func evidenceChain(from summaries: [TierSummary]) -> [NetworkPerspectiveDiagnosis.TierEvidence] {
        summaries.map { summary in
            NetworkPerspectiveDiagnosis.TierEvidence(
                tier: summary.tier,
                totalCount: summary.observed.count,
                healthyCount: summary.healthy.count,
                degradedCount: summary.degraded.count,
                downCount: summary.down.count
            )
        }
    }

    private func names(_ hostHealth: [ObservedHost]) -> String {
        let names = hostHealth.prefix(3).map(\.host.displayName).joined(separator: ", ")
        let extraCount = hostHealth.count - 3
        return extraCount > 0 ? "\(names), +\(extraCount) more" : names
    }
}
