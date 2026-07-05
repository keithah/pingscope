actor AsyncFirstResult<Value: Sendable> {
    private var result: Value?
    private var continuations: [CheckedContinuation<Value, Never>] = []

    func finish(_ value: Value) {
        guard result == nil else { return }
        result = value
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: value)
        }
    }

    func value() async -> Value {
        if let result {
            return result
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
