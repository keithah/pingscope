@testable import PingScope
import AppKit
import PingScopeCore
import SwiftUI
import XCTest

/// Renders the real multi-host graph offscreen and compares pixels.
@MainActor
final class LatencyGraphLegendLayoutTests: XCTestCase {
    /// The overlay's graph area at its default size, and a roomy one.
    private let sizes = [NSSize(width: 256, height: 62), NSSize(width: 600, height: 300)]

    private let series: [HostLatencyGraphSeries] = {
        let now = Date()
        return ["Cloudflare DNS", "Google DNS", "Default Gateway"].enumerated().map { index, name in
            let host = HostConfig(displayName: name, address: "192.0.2.\(index + 1)")
            let samples = (0..<30).map { step in
                PingResult(
                    hostID: host.id,
                    timestamp: now.addingTimeInterval(Double(step - 30) * 2),
                    // Mostly low with one spike: lines hug the bottom of the plot.
                    latency: .milliseconds(step == 10 ? 90 : Double(6 + (step + index) % 5)),
                    failureReason: nil
                )
            }
            return HostLatencyGraphSeries(host: host, samples: samples, isPrimary: index == 0)
        }
    }()

    private func graph(showsAxes: Bool, showsLegend: Bool) -> MultiHostLatencyGraph {
        MultiHostLatencyGraph(series: series, showsAxes: showsAxes, showsLegend: showsLegend)
    }

    /// Height the legend adds to the graph: its row plus the gap above it.
    private func legendRowHeight(showsAxes: Bool, width: CGFloat) -> CGFloat {
        func minimumHeight(_ showsLegend: Bool) -> CGFloat {
            NSHostingController(rootView: graph(showsAxes: showsAxes, showsLegend: showsLegend))
                .sizeThatFits(in: CGSize(width: width, height: 0)).height
        }
        return minimumHeight(true) - minimumHeight(false)
    }

    private struct Render {
        let rep: NSBitmapImageRep
        var scale: CGFloat { CGFloat(rep.pixelsHigh) / rep.size.height }

        /// Bytes of the pixel rows covering `points`, measured down from the top.
        func rows(_ points: Range<CGFloat>) -> [UInt8] {
            guard let data = rep.bitmapData else { return [] }
            let first = Int((points.lowerBound * scale).rounded()), last = Int((points.upperBound * scale).rounded())
            return Array(UnsafeBufferPointer(start: data + first * rep.bytesPerRow, count: (last - first) * rep.bytesPerRow))
        }

        /// Leftmost x, in points, with anything drawn in those rows.
        func leftmostInk(in points: Range<CGFloat>) -> CGFloat? {
            let first = Int((points.lowerBound * scale).rounded()), last = Int((points.upperBound * scale).rounded())
            for x in 0..<rep.pixelsWide {
                for y in first..<last where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                    return CGFloat(x) / scale
                }
            }
            return nil
        }
    }

    private func render(showsAxes: Bool, showsLegend: Bool, size: NSSize) -> Render? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        defer { window.close() }
        let host = NSHostingView(rootView: graph(showsAxes: showsAxes, showsLegend: showsLegend))
        window.contentView = host
        window.setContentSize(size)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return Render(rep: rep)
    }

    /// Share of the drawn bytes that differ by more than antialiasing noise.
    private func mismatch(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count else { return 1 }
        var drawn = 0, different = 0
        for (left, right) in zip(lhs, rhs) {
            if left != 0 || right != 0 { drawn += 1 }
            if abs(Int(left) - Int(right)) > 24 { different += 1 }
        }
        return Double(different) / Double(max(drawn, 1))
    }

    func testNothingIsDrawnOverThePlot() {
        for showsAxes in [false, true] {
            for size in sizes {
                let context = "axes=\(showsAxes) \(size)"
                let plotHeight = size.height - legendRowHeight(showsAxes: showsAxes, width: size.width)
                guard let withLegend = render(showsAxes: showsAxes, showsLegend: true, size: size),
                      let plotAlone = render(
                          showsAxes: showsAxes,
                          showsLegend: false,
                          size: NSSize(width: size.width, height: plotHeight)
                      ) else {
                    XCTFail("could not render \(context)")
                    continue
                }
                let plotRows = withLegend.rows(0..<plotHeight)

                XCTAssertTrue(plotRows.contains { $0 != 0 }, "the plot is blank, so this proves nothing: \(context)")
                // The same picture as this graph with no legend at all, so the
                // legend cannot be covering any of it. Laid over the plot, it
                // changes 10-90% of what is drawn.
                XCTAssertLessThan(
                    mismatch(plotRows, plotAlone.rows(0..<plotHeight)),
                    0.01,
                    "the legend changes the plot: \(context)"
                )
            }
        }
    }

    func testTheLegendIsDrawnInItsOwnRowBelowThePlot() {
        for showsAxes in [false, true] {
            for size in sizes {
                let rowHeight = legendRowHeight(showsAxes: showsAxes, width: size.width)
                let legendRows = render(showsAxes: showsAxes, showsLegend: true, size: size)?
                    .rows((size.height - rowHeight)..<size.height) ?? []

                XCTAssertGreaterThan(rowHeight, 0)
                XCTAssertTrue(legendRows.contains { $0 != 0 }, "no legend drawn: axes=\(showsAxes) \(size)")
            }
        }
    }

    func testThePlotKeepsMostOfTheOverlaysSmallGraphArea() {
        let size = sizes[0]

        XCTAssertLessThanOrEqual(legendRowHeight(showsAxes: false, width: size.width), size.height * 0.3)
    }

    func testLegendStartsAtThePlotsLeftEdge() {
        let size = sizes[1]
        for (showsAxes, expected) in [(false, CGFloat(0)), (true, CGFloat(40))] {
            let rowHeight = legendRowHeight(showsAxes: showsAxes, width: size.width)
            guard rowHeight > 4 else {
                XCTFail("the legend has no row of its own: axes=\(showsAxes)")
                continue
            }
            // Skips the 4pt gap between the plot and the legend.
            let left = render(showsAxes: showsAxes, showsLegend: true, size: size)?
                .leftmostInk(in: (size.height - rowHeight + 4)..<size.height)

            XCTAssertEqual(left ?? -1, expected, accuracy: 1.5, "axes=\(showsAxes)")
        }
    }
}
