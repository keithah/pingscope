import XCTest
@testable import PingScopeExtensionSupport

final class WidgetTimelineAndFamilyPolicyTests: XCTestCase {
    func testWidgetTimelineIncludesFutureRefreshesAndExactStaleTransition() {
        let now = Date(timeIntervalSince1970: 10_000)
        let generatedAt = now.addingTimeInterval(-5 * 60)

        let dates = WidgetTimelineSchedule.entryDates(
            now: now,
            contentGeneratedAt: generatedAt
        )

        XCTAssertGreaterThan(dates.count, 1)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(generatedAt.addingTimeInterval(15 * 60)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(10 * 60)))
        XCTAssertTrue(dates.allSatisfy { $0 >= now })
    }

    func testWidgetFamilyGraphPolicyIsConsistentForEveryFamilyWithRoom() {
        XCTAssertFalse(WidgetFamilyRenderPolicy.forFamily(.small).showsSparkline)
        XCTAssertTrue(WidgetFamilyRenderPolicy.forFamily(.medium).showsSparkline)
        XCTAssertTrue(WidgetFamilyRenderPolicy.forFamily(.large).showsSparkline)
    }

    func testEveryWidgetFamilyRendersAnExplicitStalenessMarker() {
        for family in WidgetRenderFamily.allCases {
            XCTAssertTrue(WidgetFamilyRenderPolicy.forFamily(family).showsStalenessMarker)
        }
    }
}
