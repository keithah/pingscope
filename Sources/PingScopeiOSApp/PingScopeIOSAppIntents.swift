import AppIntents
import Foundation
import PingScopeCore
import PingScopeiOS

struct PingScopeHostEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "PingScope Host")
    static let defaultQuery = PingScopeHostEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }

    init(host: HostConfig) {
        id = host.id.uuidString
        name = host.displayName
    }
}

struct PingScopeHostEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PingScopeHostEntity] {
        let requested = Set(identifiers.compactMap(UUID.init(uuidString:)))
        return configuredHosts()
            .filter { requested.contains($0.id) }
            .map(PingScopeHostEntity.init(host:))
    }

    func suggestedEntities() async throws -> [PingScopeHostEntity] {
        configuredHosts().map(PingScopeHostEntity.init(host:))
    }

    private func configuredHosts() -> [HostConfig] {
        PingScopeIOSHostStore().load().hosts
    }
}

struct StartPingScopeMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "Start PingScope Monitoring"
    static let description = IntentDescription("Start monitoring the current scope or a configured host.")
    static let openAppWhenRun = true

    @Parameter(title: "Host")
    var host: PingScopeHostEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hostID: UUID?
        if let host {
            let configuredHosts = PingScopeIOSHostStore().load().hosts
            switch PingScopeIOSIntentHostResolver.resolve(
                PingScopeIOSIntentHostReference(id: UUID(uuidString: host.id), name: host.name),
                in: configuredHosts
            ) {
            case let .found(configuredHost):
                hostID = configuredHost.id
            case .notFound:
                throw PingScopeIntentError.hostNotFound(host.name)
            }
        } else {
            hostID = nil
        }

        guard PingScopeIOSIntentCommandStore().enqueue(.start(hostID: hostID)) else {
            throw PingScopeIntentError.commandUnavailable
        }
        let message = host.map { "Starting monitoring for \($0.name)." } ?? "Starting PingScope monitoring."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopPingScopeMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop PingScope Monitoring"
    static let description = IntentDescription("Stop the current PingScope monitoring session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PingScopeIOSIntentCommandStore().enqueue(.stop) else {
            throw PingScopeIntentError.commandUnavailable
        }
        return .result(dialog: "Stopping PingScope monitoring.")
    }
}

struct PingScopeCurrentStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get PingScope Status"
    static let description = IntentDescription("Read the latest status already published by PingScope.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = await WidgetSnapshotStore().load()
        let output = PingScopeIOSStatusIntentProjection(snapshot: snapshot).outputText
        return .result(value: output, dialog: IntentDialog(stringLiteral: output))
    }
}

struct PingScopeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPingScopeMonitoringIntent(),
            phrases: ["Start monitoring with \(.applicationName)"],
            shortTitle: "Start Monitoring",
            systemImageName: "wave.3.right.circle.fill"
        )
        AppShortcut(
            intent: StopPingScopeMonitoringIntent(),
            phrases: ["Stop monitoring with \(.applicationName)"],
            shortTitle: "Stop Monitoring",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: PingScopeCurrentStatusIntent(),
            phrases: ["Get status from \(.applicationName)"],
            shortTitle: "Current Status",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
    }
}

private enum PingScopeIntentError: LocalizedError {
    case hostNotFound(String)
    case commandUnavailable

    var errorDescription: String? {
        switch self {
        case let .hostNotFound(name):
            "The configured host “\(name)” could not be found."
        case .commandUnavailable:
            "PingScope could not save the monitoring request."
        }
    }
}
