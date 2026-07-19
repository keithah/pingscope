import XCTest
@testable import PingScopeHistoryKit

final class PingScopeIOSGraphPointSearchTests: XCTestCase {
    func testNearestPointMatchesFlatScanOracleAcrossCombinedChronologicalSeries() {
        let points = [
            point(at: 10, latency: 100),
            point(at: 10, latency: 101),
            point(at: 15, latency: 150),
            point(at: 30, latency: 300),
            point(at: 45, latency: 450),
        ]

        for targetSeconds in stride(from: 0.0, through: 55.0, by: 0.5) {
            let target = date(targetSeconds)
            let oracle = points.enumerated().min { lhs, rhs in
                let lhsDistance = abs(lhs.element.timestamp.timeIntervalSince(target))
                let rhsDistance = abs(rhs.element.timestamp.timeIntervalSince(target))
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.offset < rhs.offset
            }?.element

            XCTAssertEqual(
                PingScopeIOSLatencyGraphPoint.nearest(to: target, in: points),
                oracle,
                "target=\(targetSeconds)"
            )
        }
    }

    func testNearestPointHandlesEmptyAndTargetsOutsideRenderedRange() {
        let points = [
            point(at: 10, latency: 10),
            point(at: 20, latency: 20),
            point(at: 30, latency: 30),
        ]

        XCTAssertNil(PingScopeIOSLatencyGraphPoint.nearest(to: date(20), in: []))
        XCTAssertEqual(
            PingScopeIOSLatencyGraphPoint.nearest(to: date(0), in: points),
            points.first
        )
        XCTAssertEqual(
            PingScopeIOSLatencyGraphPoint.nearest(to: date(40), in: points),
            points.last
        )
    }

    func testNearestPointChoosesEarlierRenderedPointForEquidistantTie() {
        let points = [
            point(at: 10, latency: 10),
            point(at: 20, latency: 20),
            point(at: 30, latency: 30),
        ]

        XCTAssertEqual(
            PingScopeIOSLatencyGraphPoint.nearest(to: date(25), in: points),
            points[1]
        )
        XCTAssertEqual(
            PingScopeIOSLatencyGraphPoint.nearest(to: date(20), in: points),
            points[1]
        )
    }

    func testNearestPointUsesFirstRenderedPointWhenTimestampsAreEqual() {
        let points = [
            point(at: 10, latency: 10),
            point(at: 20, latency: 20),
            point(at: 20, latency: 21),
        ]

        XCTAssertEqual(
            PingScopeIOSLatencyGraphPoint.nearest(to: date(20), in: points),
            points[1]
        )
    }

    private func point(at seconds: TimeInterval, latency: Double) -> PingScopeIOSLatencyGraphPoint {
        PingScopeIOSLatencyGraphPoint(timestamp: date(seconds), latencyMilliseconds: latency)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
