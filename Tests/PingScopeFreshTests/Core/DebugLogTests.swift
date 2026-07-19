import XCTest
@testable import PingScopeCore

final class DebugLogTests: XCTestCase {
    func testBoundedFIFOBufferOverwritesOldestElementAndKeepsFIFOOrder() {
        var buffer = BoundedFIFOBuffer<String>(capacity: 3)

        XCTAssertNil(buffer.append("one"))
        XCTAssertNil(buffer.append("two"))
        XCTAssertNil(buffer.append("three"))
        XCTAssertEqual(buffer.append("four"), "one")
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.popFirst(), "two")
        XCTAssertEqual(buffer.popFirst(), "three")
        XCTAssertEqual(buffer.popFirst(), "four")
        XCTAssertNil(buffer.popFirst())
    }

    func testWriteBurstUsesBoundedPendingQueueAndFlushPersistsNewestMarker() async {
        DebugLog.clear()
        await DebugLog.flush()

        for index in 0..<10_000 {
            DebugLog.write("burst-\(index)-" + String(repeating: "x", count: 96))
            XCTAssertLessThanOrEqual(DebugLog.pendingWriteCount, DebugLog.pendingWriteCapacity)
        }
        DebugLog.write("burst-final-marker")
        await DebugLog.flush()

        let tail = await DebugLog.recentText(maxBytes: 4_096)
        XCTAssertTrue(tail.contains("burst-final-marker"), "flush must persist the newest retained write")
    }

    func testFlushIsBarrierForWritesIssuedBeforeIt() async {
        DebugLog.clear()
        await DebugLog.flush()

        DebugLog.write("before-flush-1")
        DebugLog.write("before-flush-2")
        await DebugLog.flush()

        let text = await DebugLog.recentText(maxBytes: 1_024)
        XCTAssertTrue(text.contains("before-flush-1"))
        XCTAssertTrue(text.contains("before-flush-2"))
    }

    func testClearSeparatesQueuedDrainFromPostClearWritesAndDropAccounting() async {
        DebugLog.clear()
        await DebugLog.flush()

        // Freeze the actual serial writer so the pre-clear drain, clear
        // barrier, and post-clear overload are queued in a deterministic order.
        DebugLog.queue.suspend()
        DebugLog.write("pre-clear-marker")
        DebugLog.clear()
        for index in 0..<(DebugLog.pendingWriteCapacity + 100) {
            DebugLog.write("post-clear-\(index)")
        }
        DebugLog.write("post-clear-final-marker")
        DebugLog.queue.resume()

        await DebugLog.flush()
        let text = await DebugLog.recentText(maxBytes: 512 * 1_024)

        XCTAssertFalse(text.contains("pre-clear-marker"))
        XCTAssertTrue(text.contains("post-clear-final-marker"))
        XCTAssertTrue(
            text.contains("dropped 102 queued log message(s)"),
            "post-clear overload accounting must survive the clear barrier"
        )
    }

    func testRecentTextReturnsOnlyRequestedTail() async {
        DebugLog.clear()
        await DebugLog.flush()
        DebugLog.write("head-marker-" + String(repeating: "a", count: 2_048))
        DebugLog.write("tail-marker")
        await DebugLog.flush()

        let tail = await DebugLog.recentText(maxBytes: 64)

        XCTAssertLessThanOrEqual(tail.utf8.count, 64)
        XCTAssertTrue(tail.contains("tail-marker"))
        XCTAssertFalse(tail.contains("head-marker"))
    }
}
