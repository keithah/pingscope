import XCTest
@testable import PingScopeCore

final class BoundedBufferTests: XCTestCase {
    func testRepeatedWrappedPopsReuseRingSlotsAndPreservePrependDropSemantics() throws {
        var buffer = BoundedBuffer<Int>(capacity: 4)
        for value in 1...6 {
            buffer.append(value)
        }

        XCTAssertEqual(buffer.elements, [3, 4, 5, 6])
        XCTAssertEqual(buffer.droppedCount, 2)
        XCTAssertEqual(buffer.popPrefix(1), [3])
        XCTAssertEqual(buffer.elements, [4, 5, 6])
        XCTAssertEqual(try ringStorageSlotCount(buffer), 4)
        XCTAssertEqual(try ringStartIndex(buffer), 3)

        XCTAssertEqual(buffer.append(7), 0)
        XCTAssertEqual(buffer.popPrefix(2), [4, 5])
        XCTAssertEqual(buffer.append(8), 0)
        XCTAssertEqual(buffer.append(9), 0)
        XCTAssertEqual(buffer.elements, [6, 7, 8, 9])
        XCTAssertEqual(buffer.droppedCount, 2)
        XCTAssertEqual(try ringStorageSlotCount(buffer), 4)
        XCTAssertEqual(try ringStartIndex(buffer), 1)

        XCTAssertEqual(buffer.popPrefix(1), [6])
        buffer.prepend(contentsOf: [5, 6])
        XCTAssertEqual(buffer.elements, [5, 6, 7, 8])
        XCTAssertEqual(buffer.droppedCount, 3)
        XCTAssertEqual(buffer.popPrefix(2), [5, 6])
        XCTAssertEqual(buffer.append(10), 0)
        XCTAssertEqual(buffer.append(11), 0)
        XCTAssertEqual(buffer.elements, [7, 8, 10, 11])
        XCTAssertEqual(try ringStorageSlotCount(buffer), 4)
    }

    private func ringStorageSlotCount<Element>(_ buffer: BoundedBuffer<Element>) throws -> Int {
        let storage = try XCTUnwrap(Mirror(reflecting: buffer).children.first { $0.label == "storage" })
        return Mirror(reflecting: storage.value).children.count
    }

    private func ringStartIndex<Element>(_ buffer: BoundedBuffer<Element>) throws -> Int {
        let startIndex = try XCTUnwrap(Mirror(reflecting: buffer).children.first { $0.label == "startIndex" })
        return try XCTUnwrap(startIndex.value as? Int)
    }
}
