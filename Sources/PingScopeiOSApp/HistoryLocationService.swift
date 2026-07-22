import CoreLocation
import PingScopeCore
import PingScopeiOS

@MainActor
final class HistoryLocationService {
    var onStatusChange: ((String) -> Void)?
    var onAuthorizationChange: ((PingScopeIOSHistoryLocationAuthorization) -> Void)?

    let snapshotStore: PingScopeIOSHistoryLocationSnapshotStore
    private(set) var authorization: PingScopeIOSHistoryLocationAuthorization
    private var controller: HistoryLocationController?
    private var stateMachine: PingScopeIOSHistoryLocationStateMachine
    private var activationTask: Task<Void, Never>?
    private var keepAliveEnabled = false
    private var taggingEnabled = false
    private var monitoringActive = false

    init(snapshotStore: PingScopeIOSHistoryLocationSnapshotStore = .init()) {
        self.snapshotStore = snapshotStore
        let authorization = PingScopeIOSHistoryLocationAuthorization.undetermined
        self.authorization = authorization
        self.stateMachine = PingScopeIOSHistoryLocationStateMachine(authorization: authorization)
        self.controller = nil
        handle(.authorizationChanged(authorization))
    }

    func activate() {
        guard activationTask == nil, controller == nil else { return }
        activationTask = Task { [weak self] in
            // Core Location may synchronously wait on locationd here. Keep that
            // XPC wait off the main actor so scene creation cannot hit the watchdog.
            let status = await Task.detached {
                CLLocationManager.authorizationStatus()
            }.value
            guard !Task.isCancelled else { return }
            self?.applyDiscoveredAuthorization(status)
        }
    }

    private func ensureController() {
        guard controller == nil else { return }
        let controller = HistoryLocationController(snapshotStore: snapshotStore)
        controller.onAuthorizationChange = { [weak self] authorization in
            self?.handle(.authorizationChanged(authorization))
        }
        controller.onError = { [weak self] message in
            self?.onStatusChange?(message)
        }
        self.controller = controller
    }

    private func applyDiscoveredAuthorization(_ status: CLAuthorizationStatus) {
        let authorization = Self.authorization(from: status)
        if authorization == .whenInUse || authorization == .always {
            ensureController()
        }
        handle(.authorizationChanged(authorization))
    }

    private static func authorization(from status: CLAuthorizationStatus) -> PingScopeIOSHistoryLocationAuthorization {
        switch status {
        case .notDetermined: .undetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
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
        ensureController()
        handle(.requestKeepAliveAuthorization)
    }

    func requestWhenInUseAuthorization() {
        ensureController()
        handle(.requestTaggingAuthorization)
    }

    func statusText() -> String {
        guard keepAliveEnabled else { return "Disabled" }
        if authorization != .always {
            switch authorization {
            case .undetermined: return "Location permission not requested"
            case .denied: return "Location permission denied"
            case .restricted: return "Location access restricted"
            case .whenInUse: return "Allow Always Location in Settings"
            case .always: return "Allowed; starts while monitoring"
            }
        }
        return monitoringActive && controller?.isRunning == true
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
        controller?.perform(commands)
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
    private(set) var authorization = PingScopeIOSHistoryLocationAuthorization.undetermined

    private let manager = CLLocationManager()
    private let snapshotStore: PingScopeIOSHistoryLocationSnapshotStore

    init(snapshotStore: PingScopeIOSHistoryLocationSnapshotStore) {
        self.snapshotStore = snapshotStore
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
    }

    private static func authorization(from status: CLAuthorizationStatus) -> PingScopeIOSHistoryLocationAuthorization {
        switch status {
        case .notDetermined: .undetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
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
            case .startMonitoringSignificantLocationChanges:
                isRunning = true
                manager.startMonitoringSignificantLocationChanges()
            case .stopUpdatingLocation:
                isRunning = false
                manager.stopUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorization = Self.authorization(from: status)
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
