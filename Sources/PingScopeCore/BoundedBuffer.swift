import Foundation

public struct BoundedBuffer<Element: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public private(set) var capacity: Int
    private var storage: [Element?]
    private var startIndex: Int
    private var storedCount: Int
    public private(set) var droppedCount: Int

    public var elements: [Element] {
        guard storedCount > 0 else { return [] }
        return (0..<storedCount).map { offset in
            storage[(startIndex + offset) % capacity]!
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
            storage[(startIndex + offset) % capacity]!
        }
    }

    public func filter(_ isIncluded: (Element) -> Bool) -> [Element] {
        guard storedCount > 0 else { return [] }
        var matches: [Element] = []
        matches.reserveCapacity(storedCount)
        for offset in 0..<storedCount {
            let element = storage[(startIndex + offset) % capacity]!
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
            let element = storage[(startIndex + offset) % capacity]!
            guard isIncluded(element) else { break }
            matches.append(element)
        }
        return Array(matches.reversed())
    }

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: nil, count: self.capacity)
        self.startIndex = 0
        self.storedCount = 0
        self.droppedCount = 0
    }

    public init(elements: [Element], capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: nil, count: self.capacity)
        self.startIndex = 0
        let retainedElements = elements.suffix(self.capacity)
        self.storedCount = retainedElements.count
        self.droppedCount = 0
        for (index, element) in retainedElements.enumerated() {
            self.storage[index] = element
        }
    }

    @discardableResult
    public mutating func append(_ element: Element) -> Int {
        if storedCount < capacity {
            let insertionIndex = (startIndex + storedCount) % capacity
            storage[insertionIndex] = element
            storedCount += 1
            return 0
        }

        storage[startIndex] = element
        startIndex = (startIndex + 1) % capacity
        droppedCount += 1
        return 1
    }

    public mutating func removeAll() {
        for index in storage.indices {
            storage[index] = nil
        }
        startIndex = 0
        storedCount = 0
    }

    public mutating func prepend(contentsOf newElements: [Element]) {
        guard !newElements.isEmpty else { return }

        if newElements.count >= capacity {
            droppedCount += storedCount + newElements.count - capacity
            for index in storage.indices {
                storage[index] = nil
            }
            startIndex = 0
            storedCount = capacity
            for (index, element) in newElements.prefix(capacity).enumerated() {
                storage[index] = element
            }
            return
        }

        let overwrittenCount = max(0, newElements.count - (capacity - storedCount))
        droppedCount += overwrittenCount
        storedCount = min(capacity, storedCount + newElements.count)
        startIndex = (startIndex - newElements.count + capacity) % capacity
        for (offset, element) in newElements.enumerated() {
            storage[(startIndex + offset) % capacity] = element
        }
    }

    public mutating func popPrefix(_ requestedCount: Int) -> [Element] {
        let prefixCount = min(max(0, requestedCount), storedCount)
        guard prefixCount > 0 else { return [] }
        var batch: [Element] = []
        batch.reserveCapacity(prefixCount)
        for offset in 0..<prefixCount {
            let index = (startIndex + offset) % capacity
            batch.append(storage[index]!)
            storage[index] = nil
        }

        storedCount -= prefixCount
        if storedCount == 0 {
            startIndex = 0
        } else {
            startIndex = (startIndex + prefixCount) % capacity
        }
        return batch
    }

    public mutating func setCapacity(_ newCapacity: Int) {
        let normalizedCapacity = max(1, newCapacity)
        guard normalizedCapacity != capacity else { return }

        let retainedElements = Array(elements.suffix(normalizedCapacity))
        capacity = normalizedCapacity
        storage = Array(repeating: nil, count: capacity)
        startIndex = 0
        storedCount = retainedElements.count
        for (index, element) in retainedElements.enumerated() {
            storage[index] = element
        }
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

}
