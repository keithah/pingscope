public struct BoundedMemo<Key: Hashable, Value> {
    private var capacity: Int
    private var values: [Key: Value] = [:]
    private var recentKeys: [Key] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "BoundedMemo capacity must be positive")
        self.capacity = capacity
    }

    public var count: Int {
        values.count
    }

    public mutating func setCapacity(_ newCapacity: Int) {
        precondition(newCapacity > 0, "BoundedMemo capacity must be positive")
        capacity = newCapacity
        while recentKeys.count > capacity {
            values.removeValue(forKey: recentKeys.removeFirst())
        }
    }

    public mutating func resolve(_ key: Key, build: () -> Value) -> Value {
        if let value = values[key] {
            markRecentlyUsed(key)
            return value
        }

        let value = build()
        values[key] = value
        markRecentlyUsed(key)
        while recentKeys.count > capacity {
            values.removeValue(forKey: recentKeys.removeFirst())
        }
        return value
    }

    private mutating func markRecentlyUsed(_ key: Key) {
        recentKeys.removeAll { $0 == key }
        recentKeys.append(key)
    }
}
