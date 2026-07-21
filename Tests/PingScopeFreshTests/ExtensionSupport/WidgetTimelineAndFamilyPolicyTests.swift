import XCTest
@testable import PingScopeCore
@testable import PingScopeExtensionSupport

final class WidgetTimelineAndFamilyPolicyTests: XCTestCase {
    func testLargeWidgetLayoutKeepsDetailRowsOnlyWhenTheyFitAlongsideKeyAndGraph() {
        XCTAssertEqual(WidgetLargeFamilyLayout(hostCount: 2).detailRowCount, 2)
        XCTAssertEqual(WidgetLargeFamilyLayout(hostCount: 3).detailRowCount, 3)
        XCTAssertEqual(WidgetLargeFamilyLayout(hostCount: 4).detailRowCount, 0)
        XCTAssertEqual(WidgetLargeFamilyLayout(hostCount: 5).detailRowCount, 0)
    }

    func testWidgetPresentationUsesFirstFiveSnapshotHostsInSavedOrderWithIndependentSeries() throws {
        let hosts = (0..<6).map { index in
            HostConfig(
                id: UUID(),
                displayName: "Host \(index + 1)",
                address: "host-\(index + 1).example"
            )
        }
        var samplesByHost: [UUID: SampleSeries] = [:]
        for index in 0..<3 {
            var series = SampleSeries(hostID: hosts[index].id)
            series.append(.success(
                hostID: hosts[index].id,
                latency: .milliseconds(Double((index + 1) * 10)),
                timestamp: Date(timeIntervalSince1970: Double(10 + index))
            ))
            series.append(.success(
                hostID: hosts[index].id,
                latency: .milliseconds(Double((index + 1) * 10 + 5)),
                timestamp: Date(timeIntervalSince1970: Double(20 + index))
            ))
            samplesByHost[hosts[index].id] = series
        }
        var failureOnly = SampleSeries(hostID: hosts[3].id)
        failureOnly.append(.failure(
            hostID: hosts[3].id,
            reason: .timeout,
            timestamp: Date(timeIntervalSince1970: 13)
        ))
        samplesByHost[hosts[3].id] = failureOnly
        var sixthSeries = SampleSeries(hostID: hosts[5].id)
        sixthSeries.append(.success(
            hostID: hosts[5].id,
            latency: .milliseconds(999),
            timestamp: Date(timeIntervalSince1970: 999)
        ))
        samplesByHost[hosts[5].id] = sixthSeries

        let source = RuntimeSnapshot(
            hosts: hosts,
            primaryHostID: hosts[0].id,
            healthByHost: [:],
            samplesByHost: samplesByHost
        )
        let snapshot = WidgetSnapshot.make(from: source, generatedAt: Date(timeIntervalSince1970: 1_000))
        let presentation = graphPresentation(snapshot)

        XCTAssertEqual(snapshot.hosts.map(\.id), hosts.map(\.id), "source monitoring must retain all six")
        XCTAssertEqual(presentation.legend.map(\.hostID), Array(hosts.prefix(5)).map(\.id))
        XCTAssertEqual(presentation.series.map(\.hostID), Array(hosts.prefix(5)).map(\.id))
        XCTAssertTrue(presentation.series.allSatisfy { series in
            series.samples.allSatisfy { $0.hostID == series.hostID }
        })
        XCTAssertTrue(presentation.series.prefix(3).allSatisfy { series in
            series.pathPoints.count == 2 && series.pathPoints.allSatisfy { $0.hostID == series.hostID }
        })
        let failureSeries = presentation.series.first { $0.hostID == hosts[3].id }
        XCTAssertEqual(failureSeries?.samples.count, 1)
        XCTAssertEqual(failureSeries?.pathPoints, [], "failure-only hosts fabricate no path")
        let emptySeries = presentation.series.first { $0.hostID == hosts[4].id }
        XCTAssertEqual(emptySeries?.samples, [])
        XCTAssertEqual(emptySeries?.pathPoints, [], "empty hosts fabricate no path")
        XCTAssertEqual(presentation.timeWindow?.start, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(presentation.timeWindow?.end, Date(timeIntervalSince1970: 22))
        XCTAssertEqual(presentation.latencyScale?.minimumMilliseconds, 10)
        XCTAssertEqual(presentation.latencyScale?.maximumMilliseconds, 35)
    }

    func testWidgetPresentationSupportsTwoThroughFiveOrderedHostKeys() {
        let hosts = (0..<5).map { index in
            WidgetGraphHost(id: UUID(), displayName: "Host \(index + 1)")
        }

        for count in 2...5 {
            let presentation = WidgetMultiHostGraphPresentation(
                hosts: Array(hosts.prefix(count)),
                samples: []
            )
            XCTAssertEqual(presentation.legend.map(\.hostID), Array(hosts.prefix(count)).map(\.id))
            XCTAssertEqual(presentation.series.map(\.hostID), Array(hosts.prefix(count)).map(\.id))
        }
    }

    func testWidgetPresentationAccessibilityLabelNamesVisibleHostsInOrder() {
        let hosts = (0..<6).map { index in
            WidgetGraphHost(id: UUID(), displayName: "Host \(index + 1)")
        }

        let presentation = WidgetMultiHostGraphPresentation(hosts: hosts, samples: [])

        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Latency history for Host 1, Host 2, Host 3, Host 4, Host 5"
        )
        XCTAssertEqual(
            WidgetMultiHostGraphPresentation(hosts: [], samples: []).accessibilityLabel,
            "No latency history"
        )
    }

    func testWidgetPresentationCarriesCustomAndAutomaticAdaptiveColorsIntoMatchingSeries() {
        let customID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let automaticID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let custom = WidgetGraphDisplayColor(
            light: WidgetGraphRGB(red: 0.2, green: 0.4, blue: 0.8),
            dark: WidgetGraphRGB(red: 0.2, green: 0.4, blue: 0.8)
        )
        let automaticResolved = ResolvedHostDisplayColor(hostID: automaticID, displayColor: nil)
        let expectedAutomatic = WidgetGraphDisplayColor(
            light: graphRGB(automaticResolved.components(for: .light)),
            dark: graphRGB(automaticResolved.components(for: .dark))
        )
        let presentation = WidgetMultiHostGraphPresentation(
            hosts: [
                WidgetGraphHost(id: customID, displayName: "Custom", displayColor: custom),
                WidgetGraphHost(id: automaticID, displayName: "Automatic"),
            ],
            samples: []
        )

        XCTAssertEqual(presentation.legend.map(\.displayColor), [custom, expectedAutomatic])
        XCTAssertEqual(presentation.series.map(\.displayColor), [custom, expectedAutomatic])
    }

    func testWidgetAutomaticColorsMatchEverySharedAdaptivePaletteToken() {
        for byte in UInt8(0)..<UInt8(64) {
            let hostID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
            let resolved = ResolvedHostDisplayColor(hostID: hostID, displayColor: nil)
            let expected = WidgetGraphDisplayColor(
                light: graphRGB(resolved.components(for: .light)),
                dark: graphRGB(resolved.components(for: .dark))
            )

            XCTAssertEqual(.automatic(for: hostID), expected)
        }
    }

    func testWidgetTimelineAllowsNormalWidgetKitRefreshBudgetBeforeExactStaleTransition() {
        let now = Date(timeIntervalSince1970: 10_000)
        let generatedAt = now.addingTimeInterval(-5 * 60)

        let dates = WidgetTimelineSchedule.entryDates(
            now: now,
            contentGeneratedAt: generatedAt,
            horizon: 90 * 60
        )

        XCTAssertGreaterThan(dates.count, 1)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(generatedAt.addingTimeInterval(60 * 60)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(10 * 60)))
        XCTAssertTrue(dates.allSatisfy { $0 >= now })
    }

    func testWidgetEntryMapperOwnsExactBoundaryClockSkewHorizonAndMissingContent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let normalRefreshDelay = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: now.addingTimeInterval(-15 * 60)
        )
        XCTAssertFalse(normalRefreshDelay[0].isStale)

        let exactBoundary = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: now.addingTimeInterval(-60 * 60)
        )
        XCTAssertTrue(exactBoundary[0].isStale)

        let futureGeneratedAt = now.addingTimeInterval(60)
        let clockSkew = WidgetTimelineEntryMapper.entries(
            now: now,
            contentGeneratedAt: futureGeneratedAt
        )
        XCTAssertFalse(clockSkew[0].isStale)
        let extendedClockSkewSchedule = WidgetTimelineSchedule.entryDates(
            now: now,
            contentGeneratedAt: futureGeneratedAt,
            horizon: 90 * 60
        )
        XCTAssertTrue(extendedClockSkewSchedule.contains(
            futureGeneratedAt.addingTimeInterval(WidgetTimelineSchedule.staleInterval)
        ))

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

    private func graphPresentation(_ snapshot: WidgetSnapshot) -> WidgetMultiHostGraphPresentation {
        WidgetMultiHostGraphPresentation(
            hosts: snapshot.hosts.map {
                WidgetGraphHost(
                    id: $0.id,
                    displayName: $0.displayName,
                    displayColor: $0.displayColor.map {
                        WidgetGraphDisplayColor(
                            light: graphRGB($0.light),
                            dark: graphRGB($0.dark)
                        )
                    }
                )
            },
            samples: snapshot.recentSamples.map {
                WidgetGraphSample(
                    id: $0.id,
                    hostID: $0.hostID,
                    timestamp: $0.timestamp,
                    latencyMilliseconds: $0.latencyMilliseconds
                )
            }
        )
    }

    private func graphRGB(_ color: HostDisplayColor) -> WidgetGraphRGB {
        WidgetGraphRGB(red: color.red, green: color.green, blue: color.blue)
    }
}
