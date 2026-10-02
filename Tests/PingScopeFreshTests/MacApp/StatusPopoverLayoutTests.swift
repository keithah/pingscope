@testable import PingScope
import AppKit
import PingScopeCore
import SwiftUI
import XCTest

/// Hosts the real status content in an offscreen window, seeded with samples.
@MainActor
final class StatusContentFixture {
    let model = PingScopeModel()
    let viewModel: StatusPopoverPresentationViewModel
    let window: NSWindow
    private let savedShowsAllHosts: Bool
    private let savedDisplayMode: PingScopeDisplayMode

    init(hostCount: Int, showsAllHosts: Bool, displayMode: PingScopeDisplayMode = .signal, samplesPerHost: Int = 60) {
        savedShowsAllHosts = model.popoverShowsAllHosts
        savedDisplayMode = model.displayMode

        var hosts: [HostConfig] = []
        var health: [UUID: HostHealth] = [:]
        var series: [UUID: SampleSeries] = [:]
        let now = Date()
        for index in 0..<hostCount {
            // Names of very different lengths: row layout must not depend on them.
            let host = HostConfig(displayName: String(repeating: "Host", count: 1 + index % 3), address: "192.0.2.\(index + 1)")
            var hostHealth = HostHealth(hostID: host.id)
            var hostSeries = SampleSeries(hostID: host.id)
            for step in 0..<samplesPerHost {
                let result = PingResult(
                    hostID: host.id,
                    timestamp: now.addingTimeInterval(Double(step - samplesPerHost) * 2),
                    latency: .milliseconds(Double(8 + (step + index) % 9)),
                    failureReason: nil
                )
                hostHealth.ingest(result)
                hostSeries.append(result)
            }
            hosts.append(host)
            health[host.id] = hostHealth
            series[host.id] = hostSeries
        }
        model.displayMode = displayMode
        model.popoverShowsAllHosts = showsAllHosts
        model.liveDisplay.updateSnapshot(
            RuntimeSnapshot(hosts: hosts, primaryHostID: hosts.first?.id, healthByHost: health, samplesByHost: series)
        )
        // Assigning the range recomputes the display presentation from the snapshot.
        model.selectedRange = .oneMinute
        model.selectedRange = .fiveMinutes

        viewModel = StatusPopoverPresentationViewModel(model: model)
        let controller = NSHostingController(
            rootView: StatusPopoverView(viewModel: viewModel).environmentObject(SoftwareUpdateController())
        )
        controller.sizingOptions = []
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MenuBarPresentationMode.statusContentSize),
            styleMask: MenuBarPresentationMode.detachedPopoverWindowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
    }

    func restoreDefaults() {
        model.popoverShowsAllHosts = savedShowsAllHosts
        model.displayMode = savedDisplayMode
        window.close()
    }

    func resize(to size: NSSize) {
        window.setContentSize(size)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    var scrollViews: [NSScrollView] {
        // Keeps descending past a match: a nested scroll view is what this is for.
        func collect(_ view: NSView) -> [NSScrollView] {
            let own = (view as? NSScrollView).map { [$0] } ?? []
            return own + view.subviews.flatMap(collect)
        }
        return window.contentView.map(collect) ?? []
    }

    /// How far the only scroll view's content overflows its viewport.
    var overflow: NSSize {
        guard let scrollView = scrollViews.first, let document = scrollView.documentView else {
            return NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
        }
        let viewport = scrollView.contentView.bounds.size
        return NSSize(width: document.frame.width - viewport.width, height: document.frame.height - viewport.height)
    }
}

@MainActor
final class StatusPopoverLayoutTests: XCTestCase {
    func testStatusContentHasExactlyOneScrollRegionInEveryMode() {
        for (hostCount, showsAllHosts, mode) in [(5, true, PingScopeDisplayMode.signal), (5, false, .signal), (5, false, .ring)] {
            let fixture = StatusContentFixture(hostCount: hostCount, showsAllHosts: showsAllHosts, displayMode: mode)
            defer { fixture.restoreDefaults() }
            fixture.resize(to: NSSize(width: 579, height: 669))

            XCTAssertEqual(fixture.scrollViews.count, 1, "allHosts=\(showsAllHosts) mode=\(mode)")
        }
    }

    func testContentFillsTheViewportExactlyWhenItFits() {
        let fixture = StatusContentFixture(hostCount: 5, showsAllHosts: true)
        defer { fixture.restoreDefaults() }

        for size in [NSSize(width: 579, height: 669), NSSize(width: 400, height: 712), NSSize(width: 900, height: 1_000)] {
            fixture.resize(to: size)

            XCTAssertEqual(fixture.overflow.height, 0, accuracy: 0.5, "height at \(size)")
            XCTAssertEqual(fixture.overflow.width, 0, accuracy: 0.5, "width at \(size)")
        }
    }

    func testEveryHeightAboveTheMinimumLayoutFitsWithoutScrolling() {
        // Sample rows snap to whole rows and hand the remainder to the graph; a
        // rounding slip would show up as overflow at some in-between height.
        let fixture = StatusContentFixture(hostCount: 5, showsAllHosts: true)
        defer { fixture.restoreDefaults() }

        for height in stride(from: 670, through: 900, by: 7) {
            fixture.resize(to: NSSize(width: 400, height: CGFloat(height)))

            XCTAssertEqual(fixture.overflow.height, 0, accuracy: 0.5, "height \(height)")
        }
    }

    func testTooShortAWindowScrollsVerticallyButNeverHorizontally() {
        let fixture = StatusContentFixture(hostCount: 12, showsAllHosts: true)
        defer { fixture.restoreDefaults() }
        fixture.resize(to: MenuBarPresentationMode.statusContentMinimumSize)

        XCTAssertGreaterThan(fixture.overflow.height, 0)
        XCTAssertLessThanOrEqual(fixture.overflow.width, 0.5)
        XCTAssertEqual(fixture.scrollViews.count, 1)
    }

    func testNarrowingAfterWideningLeavesNoHorizontalOverflow() {
        let fixture = StatusContentFixture(hostCount: 5, showsAllHosts: true)
        defer { fixture.restoreDefaults() }
        fixture.resize(to: NSSize(width: 900, height: 800))
        fixture.resize(to: NSSize(width: 400, height: 800))

        XCTAssertLessThanOrEqual(fixture.overflow.width, 0.5)
    }

    func testDefaultOpeningSizeFitsItsHostRowsWithoutScrolling() {
        for hostCount in [1, 3, 5, 7] {
            let fixture = StatusContentFixture(hostCount: hostCount, showsAllHosts: true)
            defer { fixture.restoreDefaults() }
            fixture.resize(to: MenuBarPresentationMode.statusContentSize(
                hostRowCount: fixture.viewModel.presentation.hostRowCount,
                availableHeight: 2_000
            ))

            XCTAssertEqual(fixture.viewModel.presentation.hostRowCount, hostCount)
            XCTAssertEqual(fixture.overflow.height, 0, accuracy: 0.5, "\(hostCount) hosts")
        }
    }

    func testHostRowCountIsZeroWhileOneHostIsFocused() {
        let fixture = StatusContentFixture(hostCount: 5, showsAllHosts: false)
        defer { fixture.restoreDefaults() }

        XCTAssertEqual(fixture.viewModel.presentation.hostRowCount, 0)
    }

    func testHostSparklinesShareOneWidthSoTheyLineUp() {
        // The width is a function of the row alone, never of the host's name.
        XCTAssertEqual(AllHostStatusRow.sparklineWidth(rowWidth: 368), AllHostStatusRow.sparklineWidth(rowWidth: 368))
        XCTAssertEqual(AllHostStatusRow.sparklineWidth(rowWidth: 0), AllHostStatusRow.minimumSparklineWidth)
        XCTAssertEqual(AllHostStatusRow.sparklineWidth(rowWidth: 5_000), AllHostStatusRow.maximumSparklineWidth)
        XCTAssertGreaterThan(AllHostStatusRow.sparklineWidth(rowWidth: 547), AllHostStatusRow.sparklineWidth(rowWidth: 368))
    }

    func testRecentSampleTimesIncludeSeconds() {
        var format = RecentSamplesLayout.timeFormat
        format.locale = Locale(identifier: "en_US")
        format.timeZone = TimeZone(secondsFromGMT: 0)!

        // 2001-01-01 11:43:07 UTC
        let text = Date(timeIntervalSinceReferenceDate: 11 * 3_600 + 43 * 60 + 7).formatted(format)

        XCTAssertTrue(text.contains("11:43:07"), text)
    }
}
