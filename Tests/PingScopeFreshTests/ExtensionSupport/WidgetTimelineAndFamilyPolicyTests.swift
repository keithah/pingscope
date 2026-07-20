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

    func testWidgetEntryMapperOwnsExactBoundaryClockSkewHorizonAndMissingContent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let exactBoundaryGeneratedAt = now.addingTimeInterval(-WidgetTimelineSchedule.staleInterval)
        let boundary = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: exactBoundaryGeneratedAt
        )
        XCTAssertTrue(boundary[0].isStale)

        let futureGeneratedAt = now.addingTimeInterval(60)
        let clockSkew = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: futureGeneratedAt
        )
        XCTAssertFalse(clockSkew[0].isStale)
        XCTAssertTrue(clockSkew.contains { $0.date == futureGeneratedAt.addingTimeInterval(WidgetTimelineSchedule.staleInterval) })

        let beyondHorizon = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: now.addingTimeInterval(WidgetTimelineSchedule.horizon + 60)
        )
        XCTAssertEqual(beyondHorizon.map(\.date), [
            now,
            now.addingTimeInterval(WidgetTimelineSchedule.refreshInterval),
            now.addingTimeInterval(2 * WidgetTimelineSchedule.refreshInterval),
            now.addingTimeInterval(3 * WidgetTimelineSchedule.refreshInterval),
        ])
        XCTAssertTrue(beyondHorizon.allSatisfy { !$0.isStale })

        let missing = WidgetTimelineEntryMapper.entries(now: now, contentGeneratedAt: nil)
        XCTAssertEqual(missing.map(\.date), beyondHorizon.map(\.date))
        XCTAssertTrue(missing.allSatisfy { !$0.isStale })
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
