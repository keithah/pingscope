import Foundation
import PingScopeCore
import XCTest
@testable import PingScopeHistoryKit
@testable import PingScopeiOS

final class PingScopeIOSHistoryMapPresentationTests: XCTestCase {
    func testHistoryLensPersistenceDefaultsToChartRoundTripsAndRejectsInvalidValues() throws {
        try withDefaults { defaults in

            XCTAssertEqual(defaults.pingScopeIOSHistoryLens, .chart)

            for lens in HistoryLens.allCases {
                defaults.pingScopeIOSHistoryLens = lens
                XCTAssertEqual(defaults.pingScopeIOSHistoryLens, lens)
            }

            defaults.set("unsupported", forKey: "pingScopeIOSHistoryLens")
            XCTAssertEqual(defaults.pingScopeIOSHistoryLens, .chart)
        }
    }

    func testHistoryMapLensUsesRangeDefaultUntilExplicitOverridePersists() throws {
        try withDefaults { defaults in

            XCTAssertNil(defaults.pingScopeIOSHistoryMapLensOverride)
            XCTAssertEqual(HistoryMapLens.effective(for: .h1, override: defaults.pingScopeIOSHistoryMapLensOverride), .pins)
            XCTAssertEqual(HistoryMapLens.effective(for: .h4, override: nil), .pins)
            XCTAssertEqual(HistoryMapLens.effective(for: .h12, override: nil), .pins)
            XCTAssertEqual(HistoryMapLens.effective(for: .h24, override: nil), .pins)
            XCTAssertEqual(HistoryMapLens.effective(for: .d7, override: nil), .heat)
            XCTAssertEqual(HistoryMapLens.effective(for: .d14, override: nil), .heat)
            XCTAssertEqual(HistoryMapLens.effective(for: .d30, override: nil), .heat)

            defaults.pingScopeIOSHistoryMapLensOverride = .pins
            XCTAssertEqual(defaults.pingScopeIOSHistoryMapLensOverride, .pins)
            XCTAssertEqual(HistoryMapLens.effective(for: .d30, override: defaults.pingScopeIOSHistoryMapLensOverride), .pins)

            defaults.pingScopeIOSHistoryMapLensOverride = .heat
            XCTAssertEqual(defaults.pingScopeIOSHistoryMapLensOverride, .heat)
            XCTAssertEqual(HistoryMapLens.effective(for: .h1, override: defaults.pingScopeIOSHistoryMapLensOverride), .heat)

            defaults.pingScopeIOSHistoryMapLensOverride = nil
            XCTAssertNil(defaults.object(forKey: "pingScopeIOSHistoryMapLensOverride"))
            XCTAssertEqual(HistoryMapLens.effective(for: .h1, override: nil), .pins)
        }
    }

    func testHistoryMapLensInvalidPersistenceFallsBackToNoOverride() throws {
        try withDefaults { defaults in
            defaults.set("unsupported", forKey: "pingScopeIOSHistoryMapLensOverride")

            XCTAssertNil(defaults.pingScopeIOSHistoryMapLensOverride)
            XCTAssertEqual(HistoryMapLens.effective(for: .d7, override: defaults.pingScopeIOSHistoryMapLensOverride), .heat)
        }
    }

    func testHistoryMapAuthorizationPresentationDistinguishesAllStates() {
        assertAuthorization(
            .undetermined,
            taggingOptIn: false,
            mapAvailable: false,
            showsPrompt: true,
            request: .requestWhenInUse
        )
        assertAuthorization(
            .denied,
            taggingOptIn: false,
            mapAvailable: false,
            showsPrompt: true,
            request: .openSettings
        )
        assertAuthorization(
            .restricted,
            taggingOptIn: false,
            mapAvailable: false,
            showsPrompt: true,
            request: .none
        )
        assertAuthorization(
            .whenInUse,
            taggingOptIn: true,
            mapAvailable: true,
            showsPrompt: false,
            request: .none
        )
        assertAuthorization(
            .always,
            taggingOptIn: true,
            mapAvailable: true,
            showsPrompt: false,
            request: .none
        )
    }

    func testHistoryMapPrerequisiteGuidanceExplainsPermissionLocatedSamplesAndOptionalSync() {
        let denied = try! XCTUnwrap(HistoryMapPrerequisitePresentation(
            authorization: .denied,
            taggingOptIn: false,
            locatedSampleCount: 0
        ))
        XCTAssertEqual(denied.title, "Location access is off")
        XCTAssertTrue(denied.detail.contains("Settings"))
        XCTAssertEqual(denied.actionTitle, "Open Settings")

        let empty = try! XCTUnwrap(HistoryMapPrerequisitePresentation(
            authorization: .whenInUse,
            taggingOptIn: true,
            locatedSampleCount: 0
        ))
        XCTAssertEqual(empty.title, "No location-tagged samples yet")
        XCTAssertTrue(empty.detail.contains("future samples"))
        XCTAssertTrue(empty.detail.contains("iCloud sync"))
        XCTAssertNil(empty.actionTitle)

        XCTAssertNil(HistoryMapPrerequisitePresentation(
            authorization: .always,
            taggingOptIn: true,
            locatedSampleCount: 1
        ))
    }

    func testHistoryMapAuthorizationFallsBackToChartUntilGranted() {
        XCTAssertEqual(HistoryMapAuthorizationPresentation(authorization: .undetermined, taggingOptIn: false).effectiveLens(requested: .map), .chart)
        XCTAssertEqual(HistoryMapAuthorizationPresentation(authorization: .denied, taggingOptIn: false).effectiveLens(requested: .map), .chart)
        XCTAssertEqual(HistoryMapAuthorizationPresentation(authorization: .restricted, taggingOptIn: false).effectiveLens(requested: .map), .chart)
        XCTAssertEqual(HistoryMapAuthorizationPresentation(authorization: .whenInUse, taggingOptIn: true).effectiveLens(requested: .map), .map)
        XCTAssertEqual(HistoryMapAuthorizationPresentation(authorization: .always, taggingOptIn: true).effectiveLens(requested: .chart), .chart)
    }

    func testHistoryContainerOffersOneUndeterminedOptInAndKeepsChartEffective() {
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .undetermined,
            taggingOptIn: false,
            selection: selection(),
            presentationState: .loading(selection: selection())
        )

        XCTAssertEqual(decision.effectiveLens, .chart)
        XCTAssertTrue(decision.showsContextualPermissionPrompt)
        XCTAssertEqual(decision.permissionRequest, .requestWhenInUse)
    }

    func testHistoryContainerUndeterminedAfterPrivacyResetReoffersPermissionDespitePersistedOptIn() {
        let selection = selection()
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .undetermined,
            taggingOptIn: true,
            selection: selection,
            presentationState: .loading(selection: selection)
        )

        XCTAssertFalse(decision.isMapAvailable)
        XCTAssertEqual(decision.effectiveLens, .chart)
        XCTAssertTrue(decision.showsContextualPermissionPrompt)
        XCTAssertEqual(decision.permissionRequest, .requestWhenInUse)
    }

    func testHistoryContainerExplainsDeniedPermissionWithoutRepeatingRestrictedRequest() {
        let denied = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .denied,
            taggingOptIn: false,
            selection: selection(),
            presentationState: .loading(selection: selection())
        )
        XCTAssertEqual(denied.effectiveLens, .chart)
        XCTAssertTrue(denied.showsContextualPermissionPrompt)
        XCTAssertEqual(denied.permissionRequest, .openSettings)

        let restricted = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .restricted,
            taggingOptIn: false,
            selection: selection(),
            presentationState: .loading(selection: selection())
        )
        XCTAssertEqual(restricted.effectiveLens, .chart)
        XCTAssertTrue(restricted.showsContextualPermissionPrompt)
        XCTAssertEqual(restricted.permissionRequest, .none)
    }

    func testHistoryContainerMakesMapAvailableAfterGrantAndFallsBackAfterRevocation() {
        let selection = selection()
        let state = PingScopeIOSHistoryPresentationState.loading(selection: selection)

        let granted = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: selection,
            presentationState: state
        )
        let revoked = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .denied,
            taggingOptIn: true,
            selection: selection,
            presentationState: state
        )

        XCTAssertEqual(granted.effectiveLens, .map)
        XCTAssertEqual(revoked.effectiveLens, .chart)
    }

    func testHistoryContainerGrantedWithoutTaggingOptInStaysChartOnlyAndOffersEnableAction() {
        let selection = selection()
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .always,
            taggingOptIn: false,
            selection: selection,
            presentationState: .loading(selection: selection)
        )

        XCTAssertFalse(decision.isMapAvailable)
        XCTAssertEqual(decision.effectiveLens, .chart)
        XCTAssertTrue(decision.showsContextualPermissionPrompt)
        XCTAssertEqual(decision.permissionRequest, .enableTagging)
    }

    func testHistoryContainerGrantedWithTaggingOptInExposesMapWithoutPermissionRequest() {
        let selection = selection()
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: selection,
            presentationState: .loading(selection: selection)
        )

        XCTAssertTrue(decision.isMapAvailable)
        XCTAssertEqual(decision.effectiveLens, .map)
        XCTAssertFalse(decision.showsContextualPermissionPrompt)
        XCTAssertEqual(decision.permissionRequest, .none)
    }

    func testLoadedLocatedSampleSuppressesContainerEmptyPrerequisiteEndToEnd() {
        let selection = selection()
        let sample = locatedSuccess(
            id: 99,
            at: 9_900,
            latency: 20,
            latitude: 37.33,
            longitude: -122.01
        )
        let endingAt = Date(timeIntervalSince1970: 10_000)
        let presentation = PingScopeIOSHistoryPresentation(
            loadResult: PingScopeIOSHistoryLoadResult(
                hostID: selection.hostID,
                range: selection.range,
                cutoff: selection.range.cutoff(endingAt: endingAt),
                endingAt: endingAt,
                samples: [sample],
                chartReduction: HistoryChartReduction(samples: [sample]),
                isCollecting: false
            )
        )
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: selection,
            presentationState: .loaded(selection: selection, presentation: presentation)
        )

        XCTAssertEqual(presentation.mapPresentation.points.count, 1)
        XCTAssertNil(decision.prerequisitePresentation)
    }

    func testHistoryContainerLensSwitchReusesExactKeyedHostRangeContent() {
        let selection = selection()
        let presentation = emptyPresentation(selection: selection)
        let state = PingScopeIOSHistoryPresentationState.loaded(
            selection: selection,
            presentation: presentation
        )

        let chart = PingScopeIOSHistoryContainerDecision(
            requestedLens: .chart,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: selection,
            presentationState: state
        )
        let map = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: selection,
            presentationState: state
        )

        XCTAssertEqual(chart.resolvedPresentation, .content(presentation))
        XCTAssertEqual(map.resolvedPresentation, .content(presentation))
        XCTAssertEqual(chart.selection, map.selection)

        let otherHost = PingScopeIOSHistorySelection(hostID: UUID(), range: selection.range)
        let mismatched = PingScopeIOSHistoryContainerDecision(
            requestedLens: .map,
            authorization: .whenInUse,
            taggingOptIn: true,
            selection: otherHost,
            presentationState: state
        )
        XCTAssertEqual(mismatched.resolvedPresentation, .loading)
    }

    func testHistoryMapPresentationFiltersUnlocatedSamplesAndMapsExactQualityBoundaries() throws {
        let samples = [
            locatedSuccess(id: 1, at: 1, latency: 29.999, latitude: 10, longitude: 10),
            locatedSuccess(id: 2, at: 2, latency: 30, latitude: 11, longitude: 11),
            locatedSuccess(id: 3, at: 3, latency: 80, latitude: 12, longitude: 12),
            locatedSuccess(id: 4, at: 4, latency: 80.001, latitude: 13, longitude: 13),
            locatedFailure(id: 5, at: 5, latitude: 14, longitude: 14),
            PingResult.success(hostID: Self.hostID, latency: .milliseconds(250), timestamp: date(6)),
        ]

        let presentation = HistoryMapPresentation(samples: samples)

        XCTAssertEqual(presentation.points.map(\.quality), [.fast, .moderate, .moderate, .slow, .failure])
        XCTAssertEqual(presentation.points.map(\.id), samples.prefix(5).map(\.id))
        XCTAssertEqual(presentation.route.count, 5)
    }

    func testHistoryMapPresentationRejectsLocationsMutatedToInvalidCoordinates() throws {
        var nonfinite = locatedSuccess(id: 1, at: 1, latency: 10, latitude: 10, longitude: 10)
        nonfinite.location?.latitude = .nan
        var outOfRange = locatedSuccess(id: 2, at: 2, latency: 20, latitude: 20, longitude: 20)
        outOfRange.location?.longitude = 181
        let valid = locatedSuccess(id: 3, at: 3, latency: 30, latitude: 30, longitude: 30)

        let presentation = HistoryMapPresentation(samples: [nonfinite, outOfRange, valid])

        XCTAssertEqual(presentation.points.map(\.id), [valid.id])
        XCTAssertEqual(presentation.route.map(\.id), [valid.id])
    }

    func testHistoryMapSpatialReductionIsBoundedAndKeepsWorstResultPerCell() throws {
        let dense = (0..<1_200).map { index in
            locatedSuccess(
                id: index,
                at: TimeInterval(index),
                latency: Double(index % 101),
                latitude: 30 + Double(index / 40) * 0.001,
                longitude: -120 + Double(index % 40) * 0.001
            )
        }
        let sameCell = [
            locatedSuccess(id: 2_000, at: 2_000, latency: 10, latitude: 40, longitude: -70),
            locatedSuccess(id: 2_001, at: 2_001, latency: 200, latitude: 40, longitude: -70),
            locatedFailure(id: 2_002, at: 2_002, latitude: 40, longitude: -70),
        ]

        let presentation = HistoryMapPresentation(samples: dense + sameCell, maximumPointCount: 500)

        XCTAssertLessThanOrEqual(presentation.points.count, 500)
        XCTAssertTrue(presentation.points.contains { $0.id == sameCell[2].id })
        XCTAssertFalse(presentation.points.contains { $0.id == sameCell[0].id })
        XCTAssertFalse(presentation.points.contains { $0.id == sameCell[1].id })
        XCTAssertEqual(presentation.summary.worstRenderedPoint?.id, sameCell[2].id)
    }

    func testHistoryMapSpatialReductionRetainsGlobalWorstWithoutOverflowingCap() throws {
        var samples = (0..<600).map { index in
            locatedSuccess(
                id: index,
                at: TimeInterval(index),
                latency: Double(index),
                latitude: Double(index / 30),
                longitude: Double(index % 30)
            )
        }
        let globalWorst = locatedFailure(id: 10_000, at: 10_000, latitude: 10, longitude: 10)
        samples.append(globalWorst)

        let presentation = HistoryMapPresentation(samples: samples, maximumPointCount: 37)

        XCTAssertLessThanOrEqual(presentation.points.count, 37)
        XCTAssertTrue(presentation.points.contains { $0.id == globalWorst.id })
        XCTAssertEqual(presentation.summary.worstRenderedPoint?.id, globalWorst.id)
    }

    func testHistoryMapSpatialReductionHandlesZeroSpanAndAntimeridianAsNearby() throws {
        let sameCoordinate = (0..<20).map {
            locatedSuccess(id: $0, at: TimeInterval($0), latency: Double($0), latitude: 35, longitude: 140)
        }
        let zeroSpan = HistoryMapPresentation(samples: sameCoordinate, maximumPointCount: 10)
        XCTAssertEqual(zeroSpan.points.count, 1)
        XCTAssertEqual(zeroSpan.points.first?.id, sameCoordinate.last?.id)

        let antimeridian = [
            locatedSuccess(id: 100, at: 1, latency: 10, latitude: 0, longitude: 179.9),
            locatedSuccess(id: 101, at: 2, latency: 20, latitude: 0, longitude: -179.9),
            locatedFailure(id: 102, at: 3, latitude: 0, longitude: 179.95),
        ]
        let reduced = HistoryMapPresentation(samples: antimeridian, maximumPointCount: 2)
        XCTAssertLessThanOrEqual(reduced.points.count, 2)
        XCTAssertTrue(reduced.points.contains { $0.id == antimeridian[2].id })
    }

    func testHistoryMapSpatialReductionHandlesSubnormalNonzeroLatitudeSpan() {
        let samples = (0..<600).map { index in
            locatedSuccess(
                id: index,
                at: TimeInterval(index),
                latency: Double(index),
                latitude: index.isMultiple(of: 2) ? 0 : .leastNonzeroMagnitude,
                longitude: -120 + Double(index) * 0.4
            )
        }

        let presentation = HistoryMapPresentation(samples: samples, maximumPointCount: 500)

        XCTAssertFalse(presentation.points.isEmpty)
        XCTAssertLessThanOrEqual(presentation.points.count, 500)
        XCTAssertTrue(presentation.points.contains { $0.id == samples.last?.id })
    }

    func testHistoryMapRouteIsChronologicalDeduplicatedBoundedAndPreservesEndpoints() throws {
        let samples = (0..<1_200).flatMap { index -> [PingResult] in
            let sample = locatedSuccess(
                id: index,
                at: TimeInterval(1_200 - index),
                latency: 10,
                latitude: Double(index) * 0.0001,
                longitude: Double(index) * 0.0001
            )
            var duplicate = sample
            duplicate.id = uuid(index + 20_000)
            duplicate.timestamp = sample.timestamp.addingTimeInterval(0.001)
            return [sample, duplicate]
        }

        let presentation = HistoryMapPresentation(samples: samples, maximumRoutePointCount: 500)
        let orderedUnique = samples.sorted { $0.timestamp < $1.timestamp }.reduce(into: [PingResult]()) { result, sample in
            guard result.last?.location?.latitude != sample.location?.latitude
                    || result.last?.location?.longitude != sample.location?.longitude else { return }
            result.append(sample)
        }

        XCTAssertEqual(presentation.route.count, 500)
        XCTAssertEqual(presentation.route.first?.latitude, orderedUnique.first?.location?.latitude)
        XCTAssertEqual(presentation.route.first?.longitude, orderedUnique.first?.location?.longitude)
        XCTAssertEqual(presentation.route.last?.latitude, orderedUnique.last?.location?.latitude)
        XCTAssertEqual(presentation.route.last?.longitude, orderedUnique.last?.location?.longitude)
        XCTAssertEqual(presentation.route.map(\.timestamp), presentation.route.map(\.timestamp).sorted())
        for pair in zip(presentation.route, presentation.route.dropFirst()) {
            XCTAssertFalse(pair.0.latitude == pair.1.latitude && pair.0.longitude == pair.1.longitude)
        }
    }

    func testHistoryMapSummaryUsesOnlyRealLocatedSuccessfulLatencyAndStoredNetworkLabels() throws {
        let samples = [
            locatedSuccess(id: 1, at: 1, latency: 12, latitude: 1, longitude: 1, networkName: "Cafe", networkInterface: "wifi"),
            locatedSuccess(id: 2, at: 2, latency: 98, latitude: 2, longitude: 2, networkName: "Cafe", networkInterface: "cellular"),
            locatedSuccess(id: 3, at: 3, latency: 40, latitude: 3, longitude: 3, networkName: nil, networkInterface: "cellular"),
            locatedFailure(id: 4, at: 4, latitude: 4, longitude: 4, networkName: nil, networkInterface: "wired"),
            PingResult.success(
                hostID: Self.hostID,
                latency: .milliseconds(1),
                timestamp: date(5),
                location: nil
            ),
        ]

        let presentation = HistoryMapPresentation(samples: samples)

        XCTAssertEqual(presentation.summary.bestLatencyMilliseconds, 12)
        XCTAssertEqual(presentation.summary.worstLatencyMilliseconds, 98)
        XCTAssertEqual(presentation.summary.networkLabels, ["Cafe", "cellular", "wired"])
        XCTAssertEqual(presentation.summary.worstRenderedPoint?.id, samples[3].id)
    }

    func testHistoryMapPresentationEmptyWindowIsEmpty() {
        let presentation = HistoryMapPresentation(samples: [])

        XCTAssertTrue(presentation.points.isEmpty)
        XCTAssertTrue(presentation.route.isEmpty)
        XCTAssertNil(presentation.summary.bestLatencyMilliseconds)
        XCTAssertNil(presentation.summary.worstLatencyMilliseconds)
        XCTAssertNil(presentation.summary.worstRenderedPoint)
        XCTAssertTrue(presentation.summary.networkLabels.isEmpty)
    }

    func testHistoryMapPointDetailUsesOnlyRealPerSampleFields() throws {
        let success = locatedSuccess(
            id: 700,
            at: 1_234,
            latency: 42.4,
            latitude: 37.7,
            longitude: -122.4,
            networkName: "Cafe Wi-Fi",
            networkInterface: "wifi"
        )
        let failure = locatedFailure(
            id: 701,
            at: 1_235,
            latitude: 37.8,
            longitude: -122.5,
            networkName: nil,
            networkInterface: "cellular"
        )
        let presentation = HistoryMapPresentation(samples: [success, failure])
        let successPoint = try XCTUnwrap(presentation.points.first { $0.id == success.id })
        let failurePoint = try XCTUnwrap(presentation.points.first { $0.id == failure.id })

        let successDetail = HistoryMapPointDetailPresentation(point: successPoint)
        XCTAssertEqual(successDetail.readingText, "42 ms")
        XCTAssertEqual(successDetail.outcomeText, "Success")
        XCTAssertEqual(successDetail.networkName, "Cafe Wi-Fi")
        XCTAssertEqual(successDetail.networkInterface, "wifi")
        XCTAssertEqual(successDetail.horizontalAccuracyText, "±15 m")
        XCTAssertTrue(successDetail.accessibilitySummary.contains(success.timestamp.formatted(date: .abbreviated, time: .shortened)))
        XCTAssertFalse(successDetail.accessibilitySummary.localizedCaseInsensitiveContains("place"))
        XCTAssertFalse(successDetail.accessibilitySummary.localizedCaseInsensitiveContains("loss"))

        let failureDetail = HistoryMapPointDetailPresentation(point: failurePoint)
        XCTAssertEqual(failureDetail.readingText, "Failed")
        XCTAssertEqual(failureDetail.outcomeText, "Failure")
        XCTAssertNil(failureDetail.networkName)
        XCTAssertEqual(failureDetail.networkInterface, "cellular")
        XCTAssertEqual(failureDetail.horizontalAccuracyText, "±20 m")
        XCTAssertTrue(failureDetail.accessibilitySummary.contains("Failed"))
        XCTAssertFalse(failureDetail.accessibilitySummary.localizedCaseInsensitiveContains("loss"))
    }

    func testIOSHistorySourcesContainNoReverseGeocodingOrPlacePresentation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            repositoryRoot.appendingPathComponent("Sources/PingScopeiOS"),
            repositoryRoot.appendingPathComponent("Sources/PingScopeiOSApp"),
        ]
        let forbiddenTerms = [
            "CLGeocoder",
            "MKReverseGeocodingRequest",
            "reverseGeocode",
            "HistoryGeocodeCache",
            "detailRow(label: \"Place\"",
            "accessibilitySummary(place:",
        ]

        for sourceRoot in sourceRoots {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            ))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for term in forbiddenTerms {
                    XCTAssertFalse(
                        source.contains(term),
                        "Found forbidden privacy term \(term) in \(fileURL.path)"
                    )
                }
            }
        }
    }

    func testHistoryMapWorstZonePresentationUsesRealReadingAndExplicitFailureCue() throws {
        let success = locatedSuccess(
            id: 710,
            at: 1_240,
            latency: 94.6,
            latitude: 37.7,
            longitude: -122.4
        )
        let failure = locatedFailure(
            id: 711,
            at: 1_241,
            latitude: 37.8,
            longitude: -122.5
        )

        let successPoint = try XCTUnwrap(HistoryMapPresentation(samples: [success]).summary.worstRenderedPoint)
        let successZone = HistoryMapWorstZonePresentation(point: successPoint)
        XCTAssertEqual(successZone.readingText, "95 ms")
        XCTAssertEqual(successZone.outcomeText, "Success")
        XCTAssertTrue(successZone.accessibilitySummary.contains("Worst zone"))
        XCTAssertFalse(successZone.accessibilitySummary.localizedCaseInsensitiveContains("loss"))

        let failurePoint = try XCTUnwrap(HistoryMapPresentation(samples: [failure]).summary.worstRenderedPoint)
        let failureZone = HistoryMapWorstZonePresentation(point: failurePoint)
        XCTAssertEqual(failureZone.readingText, "Failed")
        XCTAssertEqual(failureZone.outcomeText, "Failure")
        XCTAssertTrue(failureZone.accessibilitySummary.contains("Failed"))
        XCTAssertTrue(failureZone.accessibilitySummary.contains("Failure"))
        XCTAssertFalse(failureZone.accessibilitySummary.localizedCaseInsensitiveContains("loss"))
    }

    func testHistoryPresentationBuildsMapFromExactRangedLoadSamples() throws {
        let rangedSample = locatedSuccess(id: 77, at: 100, latency: 42, latitude: 20, longitude: 30)
        let endingAt = date(200)
        let result = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h4,
            cutoff: HistoryRange.h4.cutoff(endingAt: endingAt),
            endingAt: endingAt,
            samples: [rangedSample],
            chartReduction: HistoryChartReduction(samples: [rangedSample]),
            isCollecting: false
        )

        let presentation = PingScopeIOSHistoryPresentation(loadResult: result)

        XCTAssertEqual(presentation.mapPresentation.points.map(\.id), [rangedSample.id])
        XCTAssertEqual(presentation.mapPresentation.route.map(\.id), [rangedSample.id])
    }

    func testLiveGraphReducerIsNotPointEquivalentToHistoryChartReduction() {
        let samples = (0..<2_000).map { index in
            PingResult.success(
                hostID: Self.hostID,
                latency: .milliseconds(Double((index % 7) * 10)),
                timestamp: date(TimeInterval(index))
            )
        }
        let liveData = PingScopeIOSLatencyGraphData(
            samples: samples,
            startDate: date(0),
            endDate: date(1_999)
        )
        let historyPoints = HistoryChartReduction(
            samples: samples,
            maximumBucketCount: PingScopeIOSLatencyGraphData.maximumPointCount / 2
        ).buckets.flatMap { bucket -> [PingScopeIOSLatencyGraphPoint] in
            guard let minimum = bucket.minimum else { return [] }
            let minimumPoint = PingScopeIOSLatencyGraphPoint(
                timestamp: minimum.timestamp,
                latencyMilliseconds: minimum.latencyMilliseconds
            )
            guard let maximum = bucket.maximum else { return [] }
            let maximumPoint = PingScopeIOSLatencyGraphPoint(
                timestamp: maximum.timestamp,
                latencyMilliseconds: maximum.latencyMilliseconds
            )
            if minimumPoint.timestamp <= maximumPoint.timestamp {
                return minimumPoint == maximumPoint ? [minimumPoint] : [minimumPoint, maximumPoint]
            }
            return minimumPoint == maximumPoint ? [minimumPoint] : [maximumPoint, minimumPoint]
        }

        XCTAssertNotEqual(liveData.points, historyPoints)
        XCTAssertEqual(liveData.points.first?.timestamp, date(0))
        XCTAssertEqual(liveData.points.last?.timestamp, date(1_999))
        XCTAssertLessThanOrEqual(liveData.points.count, PingScopeIOSLatencyGraphData.maximumPointCount)
    }

    private func assertAuthorization(
        _ authorization: PingScopeIOSHistoryLocationAuthorization,
        taggingOptIn: Bool,
        mapAvailable: Bool,
        showsPrompt: Bool,
        request: HistoryMapAuthorizationRequestDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let presentation = HistoryMapAuthorizationPresentation(
            authorization: authorization,
            taggingOptIn: taggingOptIn
        )
        XCTAssertEqual(presentation.isMapAvailable, mapAvailable, file: file, line: line)
        XCTAssertEqual(presentation.showsContextualPrompt, showsPrompt, file: file, line: line)
        XCTAssertEqual(presentation.requestDecision, request, file: file, line: line)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "PingScopeIOSHistoryMapPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func selection() -> PingScopeIOSHistorySelection {
        PingScopeIOSHistorySelection(hostID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, range: .h24)
    }

    private static let hostID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }

    private func locatedSuccess(
        id: Int,
        at seconds: TimeInterval,
        latency: Double,
        latitude: Double,
        longitude: Double,
        networkName: String? = nil,
        networkInterface: String? = nil
    ) -> PingResult {
        PingResult(
            id: uuid(id),
            hostID: Self.hostID,
            timestamp: date(seconds),
            latency: .milliseconds(latency),
            failureReason: nil,
            location: SampleLocation(
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: 15,
                networkName: networkName,
                networkInterface: networkInterface
            )
        )
    }

    private func locatedFailure(
        id: Int,
        at seconds: TimeInterval,
        latitude: Double,
        longitude: Double,
        networkName: String? = nil,
        networkInterface: String? = nil
    ) -> PingResult {
        PingResult(
            id: uuid(id),
            hostID: Self.hostID,
            timestamp: date(seconds),
            latency: nil,
            failureReason: .timeout,
            location: SampleLocation(
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: 20,
                networkName: networkName,
                networkInterface: networkInterface
            )
        )
    }

    private func emptyPresentation(
        selection: PingScopeIOSHistorySelection
    ) -> PingScopeIOSHistoryPresentation {
        let endingAt = Date(timeIntervalSince1970: 10_000)
        return PingScopeIOSHistoryPresentation(
            loadResult: PingScopeIOSHistoryLoadResult(
                hostID: selection.hostID,
                range: selection.range,
                cutoff: selection.range.cutoff(endingAt: endingAt),
                endingAt: endingAt,
                samples: [],
                chartReduction: HistoryChartReduction(samples: []),
                isCollecting: false
            ),
            thresholds: HostConfig.defaultInternet.thresholds
        )
    }
}
