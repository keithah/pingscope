import CoreLocation
import PingScopeCore
import PingScopeiOS

@MainActor
final class HistoryLocationService {
    var onStatusChange: ((String) -> Void)?
    var onAuthorizationChange: ((PingScopeIOSHistoryLocationAuthorization) -> Void)?

    let snapshotStore: PingScopeIOSHistoryLocationSnapshotStore
    private(set) var authorization: PingScopeIOSHistoryLocationAuthorization
    private let controller: HistoryLocationController
    private var stateMachine: PingScopeIOSHistoryLocationStateMachine
    private var keepAliveEnabled = false
    private var taggingEnabled = false
    private var monitoringActive = false

    init(snapshotStore: PingScopeIOSHistoryLocationSnapshotStore = .init()) {
        self.snapshotStore = snapshotStore
        let controller = HistoryLocationController(snapshotStore: snapshotStore)
        self.controller = controller
        let authorization = controller.authorization
        self.authorization = authorization
        self.stateMachine = PingScopeIOSHistoryLocationStateMachine(authorization: authorization)
        controller.onAuthorizationChange = { [weak self] authorization in
            self?.handle(.authorizationChanged(authorization))
        }
        controller.onError = { [weak self] message in
            self?.onStatusChange?(message)
        }
        handle(.authorizationChanged(controller.authorization))
    }

    func setState(keepAliveEnabled: Bool, taggingEnabled: Bool, monitoringActive: Bool) {
        self.keepAliveEnabled = keepAliveEnabled
        self.taggingEnabled = taggingEnabled
        self.monitoringActive = monitoringActive
        handle(.setState(
            keepAliveEnabled: keepAliveEnabled,
            taggingEnabled: taggingEnabled,
            monitoringActive: monitoringActive
        ))
    }

    func requestAlwaysAuthorization() {
        handle(.requestKeepAliveAuthorization)
    }

    func requestWhenInUseAuthorization() {
        handle(.requestTaggingAuthorization)
    }

    func statusText() -> String {
        guard keepAliveEnabled else { return "Disabled" }
        guard controller.authorization == .always else { return controller.authorizationStatusText }
        return monitoringActive && controller.isRunning
            ? "Running while monitoring"
            : "Allowed; starts while monitoring"
    }

    private func handle(_ event: PingScopeIOSHistoryLocationEvent) {
        let previousAuthorization = authorization
        let commands = stateMachine.handle(event)
        let authorization = stateMachine.authorization
        self.authorization = authorization
        snapshotStore.updateTagging(
            enabled: taggingEnabled,
            authorized: authorization == .whenInUse || authorization == .always
        )
        controller.perform(commands)
        onStatusChange?(statusText())
        if authorization != previousAuthorization {
            onAuthorizationChange?(authorization)
        }
    }
}

@MainActor
private final class HistoryLocationController: NSObject, CLLocationManagerDelegate {
    var onAuthorizationChange: ((PingScopeIOSHistoryLocationAuthorization) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isRunning = false

    private let manager = CLLocationManager()
    private let snapshotStore: PingScopeIOSHistoryLocationSnapshotStore

    init(snapshotStore: PingScopeIOSHistoryLocationSnapshotStore) {
        self.snapshotStore = snapshotStore
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: PingScopeIOSHistoryLocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: .undetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }

    var authorizationStatusText: String {
        switch authorization {
        case .undetermined: "Location permission not requested"
        case .denied: "Location permission denied"
        case .restricted: "Location access restricted"
        case .whenInUse: "Allow Always Location in Settings"
        case .always: isRunning ? "Running while monitoring" : "Allowed; starts while monitoring"
        }
    }

    func perform(_ commands: [PingScopeIOSHistoryLocationCommand]) {
        for command in commands {
            switch command {
            case .requestWhenInUseAuthorization:
                manager.requestWhenInUseAuthorization()
            case .requestAlwaysAuthorization:
                manager.requestAlwaysAuthorization()
            case let .configureAccuracy(accuracy):
                switch accuracy {
                case .tagging:
                    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    manager.distanceFilter = 50
                case .keepAlive:
                    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
                    manager.distanceFilter = 1_000
                }
            case let .setBackgroundUpdates(isEnabled):
                manager.allowsBackgroundLocationUpdates = isEnabled
                manager.showsBackgroundLocationIndicator = isEnabled
            case .startUpdatingLocation:
                isRunning = true
                manager.startUpdatingLocation()
            case .stopUpdatingLocation:
                isRunning = false
                manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            onAuthorizationChange?(authorization)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let candidates = locations.map { location in
            PingScopeIOSHistoryLocationFixCandidate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy
            )
        }
        let previous = snapshotStore.snapshot().fix
        let fix = PingScopeIOSHistoryLocationFixReducer.latestValidFix(
            from: candidates,
            preserving: previous
        )
        snapshotStore.updateFix(fix)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.onError?("Location keep alive error: \(message)")
        }
    }
}
