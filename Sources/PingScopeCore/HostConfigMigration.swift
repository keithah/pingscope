import Foundation

public struct HostConfigMigrator: Sendable {
    public init() {}

    public func migrate(_ host: HostConfig) -> HostConfig {
        guard host.isLegacyDefaultInternetTCPHost else { return host }
        var migrated = host
        migrated.apply(method: .https)
        return migrated
    }

    public func migrate(_ hosts: [HostConfig]) -> [HostConfig] {
        hosts.map(migrate)
    }
}

private extension HostConfig {
    var isLegacyDefaultInternetTCPHost: Bool {
        displayName == "Cloudflare DNS"
            && address == "1.1.1.1"
            && method == .tcp
            && port == 443
    }
}
