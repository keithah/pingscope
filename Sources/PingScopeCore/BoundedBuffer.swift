import Foundation

public struct BoundedBuffer<Element: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public private(set) var capacity: Int
    private var storage: [Element]
    private var startIndex: Int
    private var storedCount: Int
    public private(set) var droppedCount: Int

    public var elements: [Element] {
        guard storedCount > 0 else { return [] }
        return (0..<storedCount).map { offset in
            storage[(startIndex + offset) % storage.count]
        }
    }

    public var count: Int {
        storedCount
    }

    public var isEmpty: Bool {
        storedCount == 0
    }

    public func suffix(_ maxLength: Int) -> [Element] {
        let count = min(max(0, maxLength), storedCount)
        guard count > 0 else { return [] }
        let firstOffset = storedCount - count
        return (firstOffset..<storedCount).map { offset in
            storage[(startIndex + offset) % storage.count]
        }
    }

    public func filter(_ isIncluded: (Element) -> Bool) -> [Element] {
        guard storedCount > 0 else { return [] }
        var matches: [Element] = []
        matches.reserveCapacity(storedCount)
        for offset in 0..<storedCount {
            let element = storage[(startIndex + offset) % storage.count]
            if isIncluded(element) {
                matches.append(element)
            }
        }
        return matches
    }

    public func suffix(while isIncluded: (Element) -> Bool) -> [Element] {
        guard storedCount > 0 else { return [] }
        var matches: [Element] = []
        for offset in (0..<storedCount).reversed() {
            let element = storage[(startIndex + offset) % storage.count]
            guard isIncluded(element) else { break }
            matches.append(element)
        }
        return Array(matches.reversed())
    }

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = []
        self.startIndex = 0
        self.storedCount = 0
        self.droppedCount = 0
    }

    public init(elements: [Element], capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(elements.suffix(self.capacity))
        self.startIndex = 0
        self.storedCount = storage.count
        self.droppedCount = 0
    }

    @discardableResult
    public mutating func append(_ element: Element) -> Int {
        normalizeCapacityIfNeeded()

        if storedCount < capacity {
            if storage.count == capacity {
                let insertionIndex = (startIndex + storedCount) % storage.count
                storage[insertionIndex] = element
                storedCount += 1
                return 0
            }

            storage.append(element)
            storedCount += 1
            return 0
        }

        storage[startIndex] = element
        startIndex = (startIndex + 1) % storage.count
        droppedCount += 1
        return 1
    }

    public mutating func removeAll() {
        storage.removeAll()
        startIndex = 0
        storedCount = 0
    }

    public mutating func prepend(contentsOf newElements: [Element]) {
        guard !newElements.isEmpty else { return }
        normalizeCapacityIfNeeded()

        if newElements.count >= capacity {
            droppedCount += storedCount + newElements.count - capacity
            storage = Array(newElements.prefix(capacity))
            startIndex = 0
            storedCount = storage.count
            return
        }

        guard storage.count == capacity else {
            let combined = newElements + elements
            let kept = Array(combined.prefix(capacity))
            droppedCount += max(0, combined.count - kept.count)
            storage = kept
            startIndex = 0
            storedCount = kept.count
            return
        }

        let overwrittenCount = max(0, newElements.count - (capacity - storedCount))
        droppedCount += overwrittenCount
        storedCount = min(capacity, storedCount + newElements.count)
        startIndex = (startIndex - newElements.count + storage.count) % storage.count
        for (offset, element) in newElements.enumerated() {
            storage[(startIndex + offset) % storage.count] = element
        }
    }

    public mutating func popPrefix(_ requestedCount: Int) -> [Element] {
        let prefixCount = min(max(0, requestedCount), storedCount)
        guard prefixCount > 0 else { return [] }
        var batch: [Element] = []
        batch.reserveCapacity(prefixCount)
        for offset in 0..<prefixCount {
            batch.append(storage[(startIndex + offset) % storage.count])
        }

        let remainingCount = storedCount - prefixCount
        if remainingCount == 0 {
            storage.removeAll(keepingCapacity: true)
            startIndex = 0
            storedCount = 0
            return batch
        }

        storage = (prefixCount..<storedCount).map { offset in
            storage[(startIndex + offset) % storage.count]
        }
        storage.reserveCapacity(capacity)
        startIndex = 0
        storedCount = remainingCount
        return batch
    }

    public mutating func setCapacity(_ newCapacity: Int) {
        capacity = max(1, newCapacity)
        normalizeCapacityIfNeeded()
    }

    private enum CodingKeys: String, CodingKey {
        case capacity
        case elements
        case droppedCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCapacity = try container.decode(Int.self, forKey: .capacity)
        let decodedElements = try container.decode([Element].self, forKey: .elements)
        self.init(elements: decodedElements, capacity: decodedCapacity)
        self.droppedCount = try container.decodeIfPresent(Int.self, forKey: .droppedCount) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(elements, forKey: .elements)
        try container.encode(droppedCount, forKey: .droppedCount)
    }

    public static func == (lhs: BoundedBuffer<Element>, rhs: BoundedBuffer<Element>) -> Bool {
        lhs.capacity == rhs.capacity && lhs.elements == rhs.elements && lhs.droppedCount == rhs.droppedCount
    }

    private mutating func normalizeCapacityIfNeeded() {
        let normalizedCapacity = max(1, capacity)
        // Re-linearize when the buffer is wrapped (startIndex != 0) but no longer
        // physically full — this only happens after capacity grows, and leaving it
        // wrapped would make the next storage.append insert out of logical order.
        let needsRelinearize = startIndex != 0 && storage.count < normalizedCapacity
        guard normalizedCapacity != capacity || storage.count > normalizedCapacity || needsRelinearize else {
            return
        }

        capacity = normalizedCapacity
        storage = Array(elements.suffix(capacity))
        startIndex = 0
        storedCount = storage.count
    }
}
