#if os(macOS)
import XCTest
import PingScopeCore
@testable import PingScope

final class MacNetworkHistoryCaptureTests: XCTestCase {
    func testMacHistoryWritePathStampsFromHolderWithoutMutatingOriginal() async throws {
        let destination = MacNetworkHistoryRecordingStore()
        let holder = NetworkCaptureSnapshotStore(snapshot: NetworkCaptureSnapshot(
            interface: "wired",
            name: "Wired",
            isVPN: true
        ))
        let store = NetworkCapturedHistoryStore(destination: destination, networkCaptureStore: holder)
        let original = PingResult.success(hostID: UUID(), latency: .milliseconds(14))

        await store.append(original)

        let first = await destination.first
        let persisted = try XCTUnwrap(first)
        XCTAssertEqual(persisted.networkInterface, "wired")
        XCTAssertEqual(persisted.networkName, "Wired")
        XCTAssertTrue(persisted.isVPN)
        XCTAssertNil(original.networkInterface)
        XCTAssertNil(original.networkName)
        XCTAssertFalse(original.isVPN)
    }
}

private actor MacNetworkHistoryRecordingStore: PingHistoryStore {
    private var values: [PingResult] = []

    var first: PingResult? { values.first }

    func append(_ result: PingResult) async { values.append(result) }
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { values }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { values }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async { values.removeAll() }
}
#endif
