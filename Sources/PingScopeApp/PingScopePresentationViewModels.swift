import Combine
import Foundation
import PingScopeCore
import SwiftUI

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
    var showsAllHosts: Bool
    var showsLegend: Bool
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
        showsAllHosts = model.overlayShowsAllHosts
        showsLegend = model.overlayShowsLegend
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
}
