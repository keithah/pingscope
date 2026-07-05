@testable import PingScopeCore
import XCTest

final class AsyncPrimitiveTests: XCTestCase {
    func testAsyncPermitPoolResumesWaitersInFIFOOrder() async throws {
        let pool = AsyncPermitPool(permits: 1)
        let recorder = IntRecorder()
        try await pool.acquire()

        let first = Task {
            try await pool.acquire()
            await recorder.append(1)
        }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task {
            try await pool.acquire()
            await recorder.append(2)
        }
        try await Task.sleep(for: .milliseconds(20))

        await pool.release()
        try await Task.sleep(for: .milliseconds(20))
        await pool.release()
        try await first.value
        try await second.value

        let values = await recorder.values
        XCTAssertEqual(values, [1, 2])
    }

    func testAsyncPermitPoolCancelledWaiterDoesNotConsumePermit() async throws {
        let pool = AsyncPermitPool(permits: 1)
        try await pool.acquire()
        let cancelledWaiter = Task {
            try await pool.acquire()
        }
        try await Task.sleep(for: .milliseconds(20))
        cancelledWaiter.cancel()

        do {
            try await cancelledWaiter.value
            XCTFail("Expected waiter cancellation")
        } catch is CancellationError {
        }

        await pool.release()
        try await pool.acquire()
    }

    func testAsyncPermitLeaseIgnoresDoubleRelease() async throws {
        let pool = AsyncPermitPool(permits: 0)
        let lease = AsyncPermitLease(pool: pool)
        await lease.release()
        await lease.release()

        try await pool.acquire()
        let secondAcquireFinished = XCTestExpectation(description: "Second acquire should remain waiting")
        secondAcquireFinished.isInverted = true
        let second = Task {
            try await pool.acquire()
            secondAcquireFinished.fulfill()
        }

        await fulfillment(of: [secondAcquireFinished], timeout: 0.1)
        second.cancel()
        _ = try? await second.value
    }

    func testAsyncFirstResultResumesAllWaitersAndIgnoresLaterFinishes() async {
        let firstResult = AsyncFirstResult<Int>()
        async let firstValue = firstResult.value()
        async let secondValue = firstResult.value()

        await firstResult.finish(7)
        await firstResult.finish(9)

        let values = await [firstValue, secondValue, firstResult.value()]
        XCTAssertEqual(values, [7, 7, 7])
    }
}

private actor IntRecorder {
    private var stored: [Int] = []

    var values: [Int] {
        stored
    }

    func append(_ value: Int) {
        stored.append(value)
    }
}
