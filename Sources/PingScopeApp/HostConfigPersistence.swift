import Foundation
import PingScopeCore

struct PersistedHostState: Equatable {
    var hosts: [HostConfig]
    var primaryHostID: UUID?
}

struct LoadedHostConfiguration {
    var hosts: [HostConfig]
    var primaryHostID: UUID?
}

enum StoredHostConfigs {
    case missing
    case decoded([HostConfig])
    case decodeFailed(Error)
}

final class HostConfigPersistence {
    private let defaults: UserDefaults
    private var lastPersistedHostState: PersistedHostState?
    private var preservesUndecodableData = false
    private let seededDefaultsKey = "didSeedDefaultHosts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadInitialConfiguration(logger: (String) -> Void) -> LoadedHostConfiguration {
        let savedHosts: [HostConfig]
        switch defaults.storedHostConfigs() {
        case .decoded(let hosts):
            savedHosts = hosts.isEmpty ? seedDefaultsIfNeeded(logger: logger) : HostConfigMigrator().migrate(hosts)
        case .missing:
            savedHosts = seedDefaultsIfNeeded(logger: logger)
        case .decodeFailed(let error):
            logger("host config decode failed; preserving stored data error=\(error.localizedDescription)")
            preservesUndecodableData = true
            savedHosts = []
        }

        let sanitizedHosts = HostConfig.sanitizedHosts(BuildFlavor.current.normalizedHosts(savedHosts))
        if !savedHosts.isEmpty, sanitizedHosts.count != savedHosts.count {
            logger("host config sanitized dropped=\(savedHosts.count - sanitizedHosts.count)")
        }
        let hosts = sanitizedHosts
        return LoadedHostConfiguration(hosts: hosts, primaryHostID: defaults.primaryHostID)
    }

    func persist(_ snapshot: RuntimeSnapshot, logger: (String) -> Void) {
        guard !preservesUndecodableData else { return }
        let hosts = HostConfig.sanitizedHosts(snapshot.hosts)
        let primaryHostID = hosts.contains { $0.id == snapshot.primaryHostID } ? snapshot.primaryHostID : hosts.first?.id
        let hostState = PersistedHostState(hosts: hosts, primaryHostID: primaryHostID)
        guard hostState != lastPersistedHostState else { return }
        do {
            try defaults.setHostConfigs(hosts)
        } catch {
            logger("host config encode failed; leaving previous persisted state error=\(error.localizedDescription)")
            return
        }
        lastPersistedHostState = hostState
        defaults.primaryHostID = primaryHostID
    }

    func allowUserManagedPersistence() {
        preservesUndecodableData = false
        lastPersistedHostState = nil
    }

    private func seedDefaultsIfNeeded(logger: (String) -> Void) -> [HostConfig] {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return [] }
        let hosts = HostConfig.sanitizedHosts(
            BuildFlavor.current.normalizedHosts(
                HostConfig.defaultHosts()
            )
        )
        guard !hosts.isEmpty else { return [] }
        do {
            try defaults.setHostConfigs(hosts)
            defaults.primaryHostID = hosts.first?.id
            defaults.set(true, forKey: seededDefaultsKey)
        } catch {
            logger("default host seed encode failed; using in-memory defaults error=\(error.localizedDescription)")
        }
        return hosts
    }
}
