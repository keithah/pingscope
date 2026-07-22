import Foundation
import PingScopeCore

extension PingScopeModel {
    func refreshNetworkEndpoints(removeMissingStarlink: Bool, retryDelays: [Duration] = []) {
        endpointRefreshTask?.cancel()
        endpointRefreshTask = Task { [weak self] in
            await self?.performNetworkEndpointDetection(removeMissingStarlink: removeMissingStarlink)
            for delay in retryDelays {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: delay.jittered())
                guard !Task.isCancelled else { return }
                await self?.performNetworkEndpointDetection(removeMissingStarlink: removeMissingStarlink)
            }
        }
    }

    func performNetworkEndpointDetection(removeMissingStarlink: Bool) async {
        let result = await Self.detectNetworkEndpointResult(
            gatewayDetector: gatewayDetector,
            gatewayEndpointResolver: gatewayEndpointResolver,
            starlinkDetector: starlinkDetector,
            removeMissingStarlink: removeMissingStarlink
        )
        guard !Task.isCancelled else { return }
        handleGatewayObservation(result.gatewayOutcome, resolvedHost: result.resolvedGateway)
        reconcileStarlinkDetection(result.starlinkOutcome, removeMissing: result.removeMissingStarlink)
    }

    nonisolated static func detectNetworkEndpointResult(
        gatewayDetector: DefaultGatewayDetector,
        gatewayEndpointResolver: DefaultGatewayEndpointResolver,
        starlinkDetector: StarlinkDishDetector,
        removeMissingStarlink: Bool
    ) async -> NetworkEndpointDetectionResult {
        DebugLog.write("network endpoint refresh started removeMissingStarlink=\(removeMissingStarlink)")
        async let gatewayOutcome = gatewayDetector.detectionOutcome()
        async let starlinkOutcome = starlinkDetector.detectionOutcome(timeout: .seconds(5))
        let gateway = await gatewayOutcome
        let resolvedGateway = await resolvedGatewayHost(from: gateway, resolver: gatewayEndpointResolver)
        let outcome = await starlinkOutcome
        return NetworkEndpointDetectionResult(
            gatewayOutcome: gateway,
            resolvedGateway: resolvedGateway,
            starlinkOutcome: outcome,
            removeMissingStarlink: removeMissingStarlink
        )
    }

    nonisolated static func resolvedGatewayHost(
        from outcome: DefaultGatewayDetector.DetectionOutcome,
        resolver: DefaultGatewayEndpointResolver
    ) async -> HostConfig? {
        guard case let .detected(host) = outcome else { return nil }
        return await resolver.resolve(address: host.address)
    }

    func reconcileStarlinkDetection(_ outcome: StarlinkDishDetector.DetectionOutcome, removeMissing: Bool) {
        switch outcome {
        case let .detected(host):
            syncStarlinkHost(host)
        case .notFound:
            DebugLog.write("starlink discovery pass missed removeMissing=\(removeMissing)")
            if removeMissing {
                removeStaleStarlinkHosts()
            }
        case .failed:
            DebugLog.write("starlink discovery failed removeMissing=\(removeMissing)")
        case .cancelled:
            DebugLog.write("starlink discovery cancelled removeMissing=\(removeMissing)")
        }
    }

    func syncStarlinkHost(_ host: HostConfig) {
        var starlinkHost = host
        let preferredPrimaryID = preferredPrimaryAfterStarlinkSync(starlinkHost)
        if let existing = snapshot.hosts.first(where: {
            $0.method == .starlink || $0.displayName == host.displayName || ($0.address == host.address && $0.port == host.port)
        }) {
            starlinkHost.id = existing.id
            starlinkHost.isEnabled = existing.isEnabled
            starlinkHost.notifications = existing.notifications
        }

        if !allowsLocalNetworkProbes {
            allowsLocalNetworkProbes = true
        }

        let isExisting = snapshot.hosts.contains { $0.id == starlinkHost.id }
        DebugLog.write("starlink dish detected address=\(DebugLog.redacted(starlinkHost.address)) existing=\(isExisting)")
        if editingHostID == starlinkHost.id {
            loadDraft(from: starlinkHost)
        }
        if let existing = snapshot.hosts.first(where: { $0.id == starlinkHost.id }), existing == starlinkHost {
            return
        }
        performAutomaticHostMutation { runtime in
            await runtime.upsertHost(starlinkHost)
            if let preferredPrimaryID {
                await runtime.selectPrimaryHost(preferredPrimaryID)
            }
            DebugLog.write("starlink host upsert requested address=\(DebugLog.redacted(starlinkHost.address))")
        }
    }

    func preferredPrimaryAfterStarlinkSync(_ starlinkHost: HostConfig) -> UUID? {
        let gatewayHost = snapshot.hosts.first { $0.displayName == "Default Gateway" }
        if gatewayHost?.address == starlinkHost.address {
            return nil
        }
        if let primary = snapshot.primaryHost, primary.method != .starlink {
            return primary.id
        }
        return gatewayHost?.id ?? snapshot.hosts.first(where: { $0.method != .starlink })?.id
    }

    func removeStaleStarlinkHosts() {
        performAutomaticHostMutation { [weak self] runtime in
            let removedIDs = await runtime.removeStarlinkHosts()
            if let editingHostID = self?.editingHostID, removedIDs.contains(editingHostID) {
                self?.clearDraftHost()
            }
            DebugLog.write("stale starlink removal completed count=\(removedIDs.count)")
        }
    }

    func syncDefaultGatewayHost(_ resolvedHost: HostConfig) {
        let existing = snapshot.hosts.first { $0.displayName == "Default Gateway" }
        if !allowsLocalNetworkProbes {
            allowsLocalNetworkProbes = true
        }

        var updated = existing ?? resolvedHost
        updated.address = resolvedHost.address
        updated.tier = resolvedHost.tier
        updated.method = resolvedHost.method
        updated.port = resolvedHost.port
        allowsLocalNetworkProbes = true
        if let existing, existing == updated {
            return
        }

        if let existing {
            DebugLog.write("default gateway host updated from \(DebugLog.redacted(existing.address)) to \(DebugLog.redacted(resolvedHost.address)) method=\(resolvedHost.method.rawValue) port=\(resolvedHost.port.map(String.init) ?? "nil")")
        } else {
            DebugLog.write("default gateway host added address=\(DebugLog.redacted(resolvedHost.address)) method=\(resolvedHost.method.rawValue) port=\(resolvedHost.port.map(String.init) ?? "nil")")
        }
        if editingHostID == updated.id {
            loadDraft(from: updated)
        }
        let isPrimary = primaryHost?.id == updated.id
        performAutomaticHostMutation { runtime in
            await runtime.upsertHost(updated)
            if isPrimary {
                await runtime.selectPrimaryHost(updated.id)
            }
        }
    }

    func ensureLocalNetworkProbesForSelectedLocalHost(_ snapshot: RuntimeSnapshot) {
        guard let primaryHost = snapshot.primaryHost,
              primaryHost.requiresLocalNetworkPermission,
              !allowsLocalNetworkProbes else {
            return
        }
        allowsLocalNetworkProbes = true
    }
}

struct NetworkEndpointDetectionResult: Sendable {
    let gatewayOutcome: DefaultGatewayDetector.DetectionOutcome
    let resolvedGateway: HostConfig?
    let starlinkOutcome: StarlinkDishDetector.DetectionOutcome
    let removeMissingStarlink: Bool
}

private extension Duration {
    func jittered() -> Duration {
        let jitter = Double.random(in: 0...max(25, milliseconds * 0.1))
        return .milliseconds(milliseconds + jitter)
    }
}
