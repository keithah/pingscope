import CoreLocation
import MapKit
import PingScopeCore
import PingScopeHistoryKit
import PingScopeiOS
import SwiftUI

struct PingScopeIOSHistoryMapView: View {
    let selection: PingScopeIOSHistorySelection
    let resolvedPresentation: PingScopeIOSResolvedHistoryPresentation
    let selectedLens: HistoryMapLens
    let onSelectLens: (HistoryMapLens) -> Void
    let onShare: (HistoryExportFormat) -> Void
    let onShareReport: (HistoryReportFormat) -> Void
    let onShareMap: (HistoryMapPresentation, HistoryMapLens, HistoryMapExportRegion) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPointID: UUID?
    @State private var visibleRegion: MKCoordinateRegion?

    var body: some View {
        Group {
            switch resolvedPresentation {
            case .loading:
                ProgressView("Loading map…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .content(history):
                mapContent(history.mapPresentation)
            }
        }
        .id(selection)
        .onChange(of: selection) {
            cameraPosition = .automatic
            selectedPointID = nil
            visibleRegion = nil
        }
    }

    @ViewBuilder
    private func mapContent(_ presentation: HistoryMapPresentation) -> some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition, selection: $selectedPointID) {
                switch selectedLens {
                case .pins:
                    if presentation.route.count > 1 {
                        MapPolyline(coordinates: presentation.route.map(coordinate))
                            .stroke(Color.accentColor.opacity(0.72), lineWidth: 3)
                    }

                    ForEach(presentation.points) { point in
                        Annotation("", coordinate: coordinate(point), anchor: .bottom) {
                            HistoryMapPin(point: point, isSelected: selectedPointID == point.id)
                        }
                        .tag(point.id)
                    }
                case .heat:
                    ForEach(presentation.points) { point in
                        MapCircle(
                            center: coordinate(point),
                            radius: max(75, point.horizontalAccuracy ?? 100)
                        )
                        .foregroundStyle(point.quality.mapColor.opacity(heatOpacity))
                        .stroke(point.quality.mapColor.opacity(heatOpacity * 0.8), lineWidth: 0.5)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
            }

            VStack(alignment: .trailing, spacing: 12) {
                mapLensControl
                if presentation.points.isEmpty {
                    noLocatedSamplesNote
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            VStack(spacing: 8) {
                if selectedLens == .pins, let point = selectedPoint(in: presentation) {
                    pinDetail(point)
                }
                mapSummary(presentation.summary, lens: selectedLens, presentation: presentation)
            }
            .padding(.horizontal, 12)
            // The root shell's floating tab bar overlays its content rather than
            // participating in the safe area. Match the History Chart clearance
            // so the map summary and selected-pin detail remain fully tappable.
            .padding(.bottom, 104)
        }
    }

    private func pinDetail(_ point: HistoryMapPoint) -> some View {
        let detail = HistoryMapPointDetailPresentation(point: point)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.readingText)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(point.quality == .failure ? Color.red : Color.primary)
                Spacer()
                Label(detail.outcomeText, systemImage: point.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(point.isSuccess ? Color.secondary : Color.red)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                if let name = detail.networkName {
                    detailRow(label: "Network", value: name)
                }
                if let interface = detail.networkInterface {
                    detailRow(label: "Interface", value: interface.capitalized)
                }
                detailRow(label: "Time", value: detail.timestamp.formatted(date: .abbreviated, time: .shortened))
                if let accuracy = detail.horizontalAccuracyText {
                    detailRow(label: "Accuracy", value: accuracy)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.accessibilitySummary)
    }

    private func detailRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontDesign(.monospaced)
        }
    }

    private func mapSummary(
        _ summary: HistoryMapSummary,
        lens: HistoryMapLens,
        presentation: HistoryMapPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 18) {
                summaryMetric("Best", latency: summary.bestLatencyMilliseconds)
                if lens == .heat, let point = summary.worstRenderedPoint {
                    worstZoneMetric(point)
                } else {
                    summaryMetric("Worst", latency: summary.worstLatencyMilliseconds)
                }
                Spacer(minLength: 4)
                Menu {
                    Section("Report Card") {
                        ForEach(HistoryReportFormat.allCases) { format in
                            Button(format.displayName) {
                                onShareReport(format)
                            }
                        }
                    }
                    Section("Data") {
                        ForEach(HistoryExportFormat.allCases) { format in
                            Button(format.displayName) {
                                onShare(format)
                            }
                        }
                    }
                    if let visibleRegion {
                        Button("Annotated Map") {
                            onShareMap(
                                presentation,
                                lens,
                                HistoryMapExportRegion(region: visibleRegion)
                            )
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Share the selected host and History range")
            }
            if !summary.networkLabels.isEmpty {
                Text("Networks: \(summary.networkLabels.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func worstZoneMetric(_ point: HistoryMapPoint) -> some View {
        let zone = HistoryMapWorstZonePresentation(point: point)
        return VStack(alignment: .leading, spacing: 2) {
            Text("WORST ZONE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(zone.readingText)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(point.quality == .failure ? Color.red : Color.primary)
            Text(zone.outcomeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(point.quality == .failure ? Color.red : Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zone.accessibilitySummary)
    }

    private var mapLensControl: some View {
        HStack(spacing: 2) {
            ForEach(HistoryMapLens.allCases, id: \.self) { lens in
                Button {
                    onSelectLens(lens)
                } label: {
                    Label(
                        lens == .pins ? "Pins" : "Heat",
                        systemImage: lens == .pins ? "mappin" : "circle.hexagongrid.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        selectedLens == lens ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lens == .pins ? "Pins map" : "Heat map")
                .accessibilityAddTraits(selectedLens == lens ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map style")
    }

    private var heatOpacity: Double {
        colorScheme == .dark ? 0.34 : 0.22
    }

    private func summaryMetric(_ label: String, latency: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(latency.map { "\(Int($0.rounded())) ms" } ?? "--")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
        }
    }

    private var noLocatedSamplesNote: some View {
        return VStack(alignment: .leading, spacing: 3) {
            Label("No location-tagged samples in this range", systemImage: "location.slash")
                .font(.subheadline.weight(.semibold))
            Text("Choose a longer range, or keep monitoring with Location Tagging enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 290, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }

    private func selectedPoint(in presentation: HistoryMapPresentation) -> HistoryMapPoint? {
        guard let selectedPointID else { return nil }
        return presentation.points.first { $0.id == selectedPointID }
    }

    private func coordinate(_ point: HistoryMapPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private func coordinate(_ point: HistoryMapRoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

private extension HistoryMapExportRegion {
    init(region: MKCoordinateRegion) {
        self.init(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
    }
}

private struct HistoryMapPin: View {
    let point: HistoryMapPoint
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: isSelected ? 34 : 28, height: isSelected ? 34 : 28)
                Image(systemName: point.quality == .failure ? "xmark" : "circle.fill")
                    .font(point.quality == .failure ? .caption.bold() : .system(size: 7))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .rotationEffect(.degrees(180))
                .foregroundStyle(color)
                .offset(y: -2)
        }
        .animation(.snappy(duration: 0.18), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryMapPointDetailPresentation(point: point).accessibilitySummary)
    }

    private var color: Color {
        point.quality.mapColor
    }
}

private extension HistoryMapQuality {
    var mapColor: Color {
        switch self {
        case .fast: Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
        case .moderate: Color(red: 1, green: 204 / 255, blue: 0)
        case .slow: Color(red: 1, green: 159 / 255, blue: 10 / 255)
        case .failure: Color(red: 1, green: 59 / 255, blue: 48 / 255)
        }
    }
}
