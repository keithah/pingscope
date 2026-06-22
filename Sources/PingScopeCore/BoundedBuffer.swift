import Foundation

public struct BoundedBuffer<Element: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public private(set) var capacity: Int
    private var storage: [Element]
    private var startIndex: Int
    private var storedCount: Int

    public var elements: [Element] {
        guard storedCount > 0 else { return [] }
        return (0..<storedCount).map { offset in
            storage[(startIndex + offset) % storage.count]
        }
    }

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = []
        self.startIndex = 0
        self.storedCount = 0
    }

    public init(elements: [Element], capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(elements.suffix(self.capacity))
        self.startIndex = 0
        self.storedCount = storage.count
    }

    public mutating func append(_ element: Element) {
        normalizeCapacityIfNeeded()

        if storage.count < capacity {
            storage.append(element)
            storedCount += 1
            return
        }

        storage[startIndex] = element
        startIndex = (startIndex + 1) % storage.count
    }

    public mutating func setCapacity(_ newCapacity: Int) {
        capacity = max(1, newCapacity)
        normalizeCapacityIfNeeded()
    }

    private enum CodingKeys: String, CodingKey {
        case capacity
        case elements
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCapacity = try container.decode(Int.self, forKey: .capacity)
        let decodedElements = try container.decode([Element].self, forKey: .elements)
        self.init(elements: decodedElements, capacity: decodedCapacity)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(elements, forKey: .elements)
    }

    public static func == (lhs: BoundedBuffer<Element>, rhs: BoundedBuffer<Element>) -> Bool {
        lhs.capacity == rhs.capacity && lhs.elements == rhs.elements
    }

    private mutating func normalizeCapacityIfNeeded() {
        let normalizedCapacity = max(1, capacity)
        guard normalizedCapacity != capacity || storage.count > normalizedCapacity else {
            return
        }

        capacity = normalizedCapacity
        storage = Array(elements.suffix(capacity))
        startIndex = 0
        storedCount = storage.count
    }
}
