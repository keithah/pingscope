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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadInitialConfiguration(logger: (String) -> Void) -> LoadedHostConfiguration {
        let savedHosts: [HostConfig]
        switch defaults.storedHostConfigs() {
        case .decoded(let hosts):
            savedHosts = HostConfigMigrator().migrate(hosts)
        case .missing:
            savedHosts = []
        case .decodeFailed(let error):
            logger("host config decode failed; preserving stored data error=\(error.localizedDescription)")
            preservesUndecodableData = true
            savedHosts = []
        }

        let hosts = savedHosts.isEmpty ? [HostConfig.defaultInternet] : BuildFlavor.current.normalizedHosts(savedHosts)
        return LoadedHostConfiguration(hosts: hosts, primaryHostID: defaults.primaryHostID)
    }

    func persist(_ snapshot: RuntimeSnapshot) {
        guard !preservesUndecodableData else { return }
        let hostState = PersistedHostState(hosts: snapshot.hosts, primaryHostID: snapshot.primaryHostID)
        guard hostState != lastPersistedHostState else { return }
        lastPersistedHostState = hostState
        defaults.hostConfigs = snapshot.hosts
        defaults.primaryHostID = snapshot.primaryHostID
    }

    func allowUserManagedPersistence() {
        preservesUndecodableData = false
        lastPersistedHostState = nil
    }
}
