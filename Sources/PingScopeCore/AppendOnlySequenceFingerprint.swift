import Foundation

/// The boundary identity used to invalidate work over an append-only sequence.
public struct AppendOnlySequenceFingerprint<Boundary: Hashable & Sendable>: Hashable, Sendable {
    public let count: Int
    public let first: Boundary?
    public let last: Boundary?

    public init(count: Int, first: Boundary?, last: Boundary?) {
        self.count = count
        self.first = first
        self.last = last
    }
}

public extension AppendOnlySequenceFingerprint where Boundary == UUID {
    init(samples: [PingResult]) {
        self.init(
            count: samples.count,
            first: samples.first?.id,
            last: samples.last?.id
        )
    }
}

/// Per-host append-only identity for presentation inputs.
public struct PerHostSampleFingerprint: Hashable, Sendable {
    public struct Host: Hashable, Sendable {
        public let hostID: UUID
        public let count: Int
        public let newestSampleID: UUID?
        public let newestTimestamp: Date?

        public init(
            hostID: UUID,
            count: Int,
            newestSampleID: UUID?,
            newestTimestamp: Date?
        ) {
            self.hostID = hostID
            self.count = count
            self.newestSampleID = newestSampleID
            self.newestTimestamp = newestTimestamp
        }
    }

    public let hosts: [Host]

    /// This is one forward pass and intentionally remains correct for unordered inputs.
    public init(samples: [PingResult]) {
        var accumulated: [UUID: (count: Int, newest: PingResult)] = [:]
        accumulated.reserveCapacity(samples.count)
        for sample in samples {
            if let current = accumulated[sample.hostID] {
                let isNewer = sample.timestamp > current.newest.timestamp
                    || (sample.timestamp == current.newest.timestamp
                        && uuidBytesAreLess(current.newest.id, sample.id))
                accumulated[sample.hostID] = (
                    count: current.count + 1,
                    newest: isNewer ? sample : current.newest
                )
            } else {
                accumulated[sample.hostID] = (count: 1, newest: sample)
            }
        }
        hosts = accumulated.map { hostID, accumulator in
            Host(
                hostID: hostID,
                count: accumulator.count,
                newestSampleID: accumulator.newest.id,
                newestTimestamp: accumulator.newest.timestamp
            )
        }
        .sorted { uuidBytesAreLess($0.hostID, $1.hostID) }
    }
}

private func uuidBytesAreLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
    var lhsBytes = lhs.uuid
    var rhsBytes = rhs.uuid
    return withUnsafeBytes(of: &lhsBytes) { lhsBuffer in
        withUnsafeBytes(of: &rhsBytes) { rhsBuffer in
            lhsBuffer.lexicographicallyPrecedes(rhsBuffer)
        }
    }
}
