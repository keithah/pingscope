import Combine
import Foundation
import PingScopeCore
import SwiftUI

enum PingScopeDisplayMode: String, CaseIterable, Identifiable {
    case signal
    case ring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signal: "Signal"
        case .ring: "Ring"
        }
    }

    func resolvedForHostScope(showsAllHosts: Bool) -> PingScopeDisplayMode {
        showsAllHosts ? .signal : self
    }
}

struct OverlayHostOption: Identifiable {
    let id: UUID
    let name: String
    let isSelected: Bool
}

struct OverlayPresentation {
    var compactMode: Bool
    var menuBarState: MenuBarState
    var hostOptions: [OverlayHostOption]
    var primaryHostName: String
    var primaryDegradedThresholdMilliseconds: Double
    var showsAllHosts: Bool
    var showsLegend: Bool
    var displayMode: PingScopeDisplayMode
    var displayPresentation: PingScopeDisplayPresentation

    @MainActor
    init(model: PingScopeModel) {
        let primaryID = model.primaryHost?.id
        compactMode = model.overlayCompactMode
        menuBarState = model.menuBarState
        hostOptions = model.snapshot.hosts.map { host in
            OverlayHostOption(
                id: host.id,
                name: host.displayName,
                isSelected: !model.overlayShowsAllHosts && host.id == primaryID
            )
        }
        primaryHostName = model.primaryHost?.displayName ?? "No Host"
        primaryDegradedThresholdMilliseconds = model.primaryHost?.thresholds.degradedMilliseconds ?? LatencyThresholds.defaults.degradedMilliseconds
        showsAllHosts = model.overlayShowsAllHosts
        showsLegend = model.overlayShowsLegend
        displayMode = model.displayMode
        displayPresentation = model.displayPresentation
    }
}

@MainActor
final class OverlayPresentationViewModel: ObservableObject {
    @Published private(set) var presentation: OverlayPresentation
    private weak var model: PingScopeModel?

    @MainActor
    init(model: PingScopeModel) {
        self.model = model
        self.presentation = OverlayPresentation(model: model)
    }

    func refresh() {
        guard let model else { return }
        presentation = OverlayPresentation(model: model)
    }

    func openDetails() {
        model?.openOverlayDetails()
    }

    func selectHost(_ id: UUID) {
        model?.overlayShowsAllHosts = false
        model?.selectHost(id)
        refresh()
    }

    func selectAllHosts() {
        model?.overlayShowsAllHosts = true
        refresh()
    }

    func toggleAllHosts() {
        guard let model else { return }
        model.overlayShowsAllHosts.toggle()
        refresh()
    }

    func toggleLegend() {
        guard let model else { return }
        model.overlayShowsLegend.toggle()
        refresh()
    }
}

struct StatusPopoverPresentation {
    var selectedRange: TimeRange
    var snapshot: RuntimeSnapshot
    var primaryHost: HostConfig?
    var popoverShowsAllHosts: Bool
    var selectedRangeState: MenuBarState
    var selectedRangeStatusLabel: String
    var displayMode: PingScopeDisplayMode
    var displayPresentation: PingScopeDisplayPresentation
    var networkDiagnosis: NetworkPerspectiveDiagnosis

    @MainActor
    init(model: PingScopeModel) {
        selectedRange = model.selectedRange
        snapshot = model.snapshot
        primaryHost = model.primaryHost
        popoverShowsAllHosts = model.popoverShowsAllHosts
        selectedRangeState = model.selectedRangeState
        selectedRangeStatusLabel = model.selectedRangeStatusLabel
        displayMode = model.displayMode
        displayPresentation = model.displayPresentation
        networkDiagnosis = model.networkDiagnosis
    }
}

@MainActor
final class StatusPopoverPresentationViewModel: ObservableObject {
    @Published private(set) var presentation: StatusPopoverPresentation
    private weak var model: PingScopeModel?

    @MainActor
    init(model: PingScopeModel) {
        self.model = model
        self.presentation = StatusPopoverPresentation(model: model)
    }

    func refresh() {
        guard let model else { return }
        presentation = StatusPopoverPresentation(model: model)
    }

    func setSelectedRange(_ range: TimeRange) {
        model?.selectedRange = range
        refresh()
    }

    func selectHost(_ id: UUID) {
        model?.popoverShowsAllHosts = false
        model?.selectHost(id)
        refresh()
    }

    func selectAllHosts() {
        model?.popoverShowsAllHosts = true
        refresh()
    }

    func setPingInterval(_ milliseconds: Int, for hostID: UUID) {
        model?.setPingInterval(.milliseconds(Double(milliseconds)), for: hostID)
        refresh()
    }

    func setPingIntervalForAllHosts(_ milliseconds: Int) {
        guard let model else { return }
        let targetHosts = presentation.snapshot.hosts.filter(\.isEnabled)
        let hosts = targetHosts.isEmpty ? presentation.snapshot.hosts : targetHosts
        for host in hosts {
            model.setPingInterval(.milliseconds(Double(milliseconds)), for: host.id)
        }
        refresh()
    }

    func setDisplayMode(_ displayMode: PingScopeDisplayMode) {
        model?.displayMode = displayMode
        refresh()
    }

    func defaultShareOptions() -> PingScopeShareGraphOptions {
        PingScopeShareGraphOptions(
            scope: .currentView,
            range: presentation.selectedRange,
            appearance: .current,
            includesTable: false
        )
    }

    func shareGraph(options: PingScopeShareGraphOptions) {
        model?.shareGraph(options: options)
    }
}
