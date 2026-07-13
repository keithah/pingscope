import Foundation
import MapKit
import PingScopeCore
import PingScopeiOS
import SwiftUI
import UIKit

/// App-target boundary for locally generated History share files. Rendering and
/// map snapshot formats can be added here later without changing Core exports.
@MainActor
final class HistoryExportService: HistoryExportServicing {
    private let structuredExporter: HistoryStructuredExportService
    private let reportFileLifecycle: HistoryReportFileLifecycle
    private let mapFileLifecycle: HistoryMapFileLifecycle

    init(
        structuredExporter: HistoryStructuredExportService? = nil,
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.structuredExporter = structuredExporter ?? HistoryStructuredExportService()
        self.reportFileLifecycle = HistoryReportFileLifecycle(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory
        )
        self.mapFileLifecycle = HistoryMapFileLifecycle(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory
        )
    }

    func exportReport(
        presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) async throws -> HistorySharePayload {
        try reportFileLifecycle.export(hostName: presentation.hostName, format: format) { destination in
            let data = try renderReport(presentation, format: format)
            try data.write(to: destination, options: .atomic)
        }
    }

    func export(
        store: any PingHistoryStore,
        host: HostConfig,
        range: HistoryRange,
        format: HistoryExportFormat,
        now: Date
    ) async throws -> HistorySharePayload {
        try await structuredExporter.export(
            store: store,
            host: host,
            range: range,
            format: format,
            now: now
        )
    }

    func exportMap(request: HistoryMapExportRequest) async throws -> HistorySharePayload {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: request.visibleRegion.centerLatitude,
                longitude: request.visibleRegion.centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: request.visibleRegion.latitudeDelta,
                longitudeDelta: request.visibleRegion.longitudeDelta
            )
        )
        options.size = CGSize(width: 1_080, height: 720)
        options.scale = 1
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await withTaskCancellationHandler {
            try await snapshotter.start()
        } onCancel: {
            snapshotter.cancel()
        }
        try Task.checkCancellation()

        let bounds = CGRect(origin: .zero, size: options.size)
        let plan = HistoryMapDrawingPlan(
            presentation: request.presentation,
            lens: request.lens,
            viewport: HistoryMapExportRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: bounds.height
            )
        ) { coordinate in
            let point = snapshot.point(for: CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
            return HistoryMapExportPoint(x: point.x, y: point.y)
        }

        return try mapFileLifecycle.export(hostName: request.host.displayName) { destination in
            try Task.checkCancellation()
            let renderer = UIGraphicsImageRenderer(size: options.size)
            let image = renderer.image { context in
                snapshot.image.draw(in: bounds)
                draw(plan, region: request.visibleRegion, in: context.cgContext, size: options.size)
            }
            guard let data = image.pngData() else {
                throw HistoryMapRenderingError.pngEncodingFailed
            }
            try data.write(to: destination, options: .atomic)
            try Task.checkCancellation()
        }
    }

    func removeTemporaryFiles(_ files: [URL]) {
        structuredExporter.removeTemporaryFiles(files)
    }

    private func renderReport(
        _ presentation: HistoryReportPresentation,
        format: HistoryReportFormat
    ) throws -> Data {
        let size = CGSize(width: 1_080, height: 720)
        let renderer = ImageRenderer(
            content: HistoryReportCard(presentation: presentation)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            throw HistoryReportRenderingError.imageRendererFailed
        }
        switch format {
        case .png:
            guard let data = image.pngData() else {
                throw HistoryReportRenderingError.pngEncodingFailed
            }
            return data
        case .pdf:
            let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
            return pdfRenderer.pdfData { context in
                context.beginPage()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    private func draw(
        _ plan: HistoryMapDrawingPlan,
        region: HistoryMapExportRegion,
        in context: CGContext,
        size: CGSize
    ) {
        context.setLineCap(.round)
        for segment in plan.routeSegments where segment.count > 1 {
            context.beginPath()
            context.move(to: cgPoint(segment[0].position))
            for point in segment.dropFirst() { context.addLine(to: cgPoint(point.position)) }
            context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.78).cgColor)
            context.setLineWidth(5)
            context.strokePath()
        }
        for pin in plan.points {
            let center = cgPoint(pin.position)
            if pin.failureCue == .octagonCross {
                drawFailureCue(center: center, radius: 12, fill: color(for: pin.quality), in: context)
            } else {
                context.setFillColor(color(for: pin.quality).cgColor)
                context.fillEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
            }
        }
        let metersPerPoint = max(1, region.latitudeDelta * 111_320 / size.height)
        for circle in plan.circles {
            let center = cgPoint(circle.center)
            let radius = min(80, max(10, circle.radiusMeters / metersPerPoint))
            context.setFillColor(color(for: circle.quality).withAlphaComponent(circle.opacity).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            if circle.failureCue == .octagonCross {
                drawFailureCue(center: center, radius: min(13, radius), fill: color(for: circle.quality), in: context)
            }
        }
    }

    private func drawFailureCue(center: CGPoint, radius: CGFloat, fill: UIColor, in context: CGContext) {
        let path = UIBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 + .pi / 8
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.close()
        context.setFillColor(fill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.5)
        context.move(to: CGPoint(x: center.x - radius * 0.45, y: center.y - radius * 0.45))
        context.addLine(to: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.45))
        context.move(to: CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.45))
        context.addLine(to: CGPoint(x: center.x - radius * 0.45, y: center.y + radius * 0.45))
        context.strokePath()
    }

    private func cgPoint(_ point: HistoryMapExportPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    private func color(for quality: HistoryMapQuality) -> UIColor {
        switch quality {
        case .fast: .systemGreen
        case .moderate: .systemYellow
        case .slow: .systemOrange
        case .failure: .systemRed
        }
    }
}

private enum HistoryReportRenderingError: LocalizedError {
    case imageRendererFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageRendererFailed: "The report card could not be rendered."
        case .pngEncodingFailed: "The report card PNG could not be encoded."
        }
    }
}

private enum HistoryMapRenderingError: LocalizedError {
    case pngEncodingFailed

    var errorDescription: String? { "The annotated map PNG could not be encoded." }
}
