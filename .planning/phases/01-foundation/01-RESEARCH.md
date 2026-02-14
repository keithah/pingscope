# Phase 1: Foundation - Research

**Researched:** 2026-02-14
**Domain:** Swift Concurrency, NWConnection, Actor-isolated Network Services
**Confidence:** HIGH

## Summary

This research investigates the patterns and pitfalls for building a PingService that measures TCP/UDP connection latency using Swift Concurrency (async/await) with proper timeout handling and connection lifecycle management. The core challenge is wrapping Apple's callback-based Network framework (NWConnection) in async/await patterns while ensuring immediate timeout enforcement, proper cancellation, and cleanup of stale connections.

The standard approach uses an actor-isolated PingService that wraps NWConnection with `withCheckedContinuation` for async/await compatibility, combined with `withThrowingTaskGroup` for timeout racing. Connection cleanup must be immediate upon completion or cancellation, with a periodic sweep as a safety net. For measuring latency, Swift 5.7+'s `ContinuousClock` provides the modern, type-safe approach.

**Primary recommendation:** Use fresh connections per ping (not pooled) for reliability, wrap NWConnection callbacks with `withCheckedContinuation`, implement timeout via task racing pattern, and leverage `withTaskCancellationHandler` for immediate connection cleanup on cancellation.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Network.framework (NWConnection) | macOS 10.14+ | TCP/UDP connections | Apple's modern networking API, App Store safe, no raw sockets |
| Swift Concurrency (async/await) | Swift 5.5+ | Async operations | Eliminates DispatchSemaphore race conditions, structured concurrency |
| ContinuousClock | Swift 5.7+ | Elapsed time measurement | Type-safe Duration, keeps ticking during sleep |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-timeout | 0.4.1 | Timeout wrapper | Optional - provides clean `withThrowingTimeout` API |
| swift-async-algorithms | 1.0+ | Debounce/Throttle | If needing to debounce rapid ping requests |
| Swift Atomics | 1.2+ | Lock-free state flags | Only if atomic cancellation flags needed outside actor |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NWConnection | URLSession | URLSession has no direct TCP latency measurement; NWConnection gives connection-level timing |
| swift-timeout package | Custom withTimeout | Hand-rolling is fine; package provides tested Swift 6 compatibility |
| ContinuousClock | CFAbsoluteTimeGetCurrent | CFAbsoluteTime works but ContinuousClock is modern, type-safe |

**Package.swift dependencies (optional):**
```swift
dependencies: [
    .package(url: "https://github.com/swhitty/swift-timeout.git", from: "0.4.0"),
]
```

## Architecture Patterns

### Recommended Project Structure
```
Sources/PingMonitor/
├── Services/
│   ├── PingService.swift         # Actor-isolated ping orchestration
│   └── ConnectionWrapper.swift   # NWConnection async wrapper
├── Models/
│   ├── PingResult.swift          # Result type with latency/error
│   └── Host.swift                # Host configuration
└── Utilities/
    └── Timeout.swift             # withTimeout helper (if not using package)
```

### Pattern 1: Actor-Isolated PingService
**What:** Use Swift actor to serialize access to shared ping state
**When to use:** Always - required for thread-safe concurrent pings
**Example:**
```swift
// Source: Swift Concurrency best practices, verified patterns
actor PingService {
    private var activePings: [UUID: Task<Void, Never>] = [:]
    private let maxConcurrent = 10

    func ping(host: String, port: UInt16, timeout: Duration) async -> PingResult {
        let id = UUID()
        let startTime = ContinuousClock.now

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.measureConnection(host: host, port: port)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw TimeoutError()
                }

                // First to complete wins
                try await group.next()
                group.cancelAll()
            }

            let elapsed = ContinuousClock.now - startTime
            return .success(latency: elapsed)
        } catch is TimeoutError {
            return .timeout
        } catch {
            return .failure(error)
        }
    }
}
```

### Pattern 2: NWConnection Async Wrapper with withCheckedContinuation
**What:** Convert NWConnection's callback-based API to async/await
**When to use:** Every NWConnection operation
**Example:**
```swift
// Source: Apple Developer Forums, withCheckedContinuation documentation
func connectAsync(host: String, port: UInt16) async throws {
    let endpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!
    )
    let connection = NWConnection(to: endpoint, using: .tcp)

    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    } onCancel: {
        connection.cancel()
    }
}
```

### Pattern 3: Timeout via Task Racing
**What:** Race the actual operation against a sleep task
**When to use:** For immediate timeout enforcement (not waiting for late responses)
**Example:**
```swift
// Source: Donny Wals - "Implementing Task timeout with Swift Concurrency"
enum TimeoutError: Error {
    case timeout
}

func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TimeoutError.timeout
        }

        defer { group.cancelAll() }

        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}
```

### Pattern 4: Throttled Concurrent Pings
**What:** Limit concurrent pings to prevent resource exhaustion
**When to use:** When pinging multiple hosts (max 10 concurrent per user decision)
**Example:**
```swift
// Source: Swift with Majid - "Mastering TaskGroups in Swift"
func pingAllHosts(_ hosts: [Host]) async -> [PingResult] {
    let maxConcurrent = 10
    var results: [PingResult] = []
    var index = 0

    await withTaskGroup(of: PingResult.self) { group in
        // Start initial batch
        for _ in 0..<min(maxConcurrent, hosts.count) {
            let host = hosts[index]
            index += 1
            group.addTask { await self.ping(host: host) }
        }

        // Add new task as each completes
        for await result in group {
            results.append(result)
            if index < hosts.count {
                let host = hosts[index]
                index += 1
                group.addTask { await self.ping(host: host) }
            }
        }
    }

    return results
}
```

### Anti-Patterns to Avoid
- **DispatchSemaphore with async/await:** Causes deadlocks; semaphores block threads that Swift Concurrency needs
- **Forgetting continuation resume:** Must resume exactly once; use defer or ensure all paths resume
- **Ignoring re-entrancy:** Actor state can change during await; verify assumptions after suspension points
- **Unbounded task creation:** Creating 1000s of tasks wastes memory; use throttling pattern
- **Storing NWConnection in actor property long-term:** Connections can become stale; create fresh per ping

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timeout wrapper | Custom timeout with timers | Task racing pattern OR swift-timeout package | Edge cases with cancellation cleanup |
| Elapsed time measurement | Date arithmetic or CFAbsoluteTimeGetCurrent | ContinuousClock.measure or .now subtraction | Type-safe, continues during sleep, modern API |
| Callback-to-async bridge | Manual state machines | withCheckedThrowingContinuation | Compiler-checked single resume, cleaner |
| Concurrent task limiting | Manual semaphores | TaskGroup with progressive addition | Works with structured concurrency, no deadlocks |

**Key insight:** Swift Concurrency provides primitives that handle edge cases (cancellation, isolation, cleanup) that manual implementations miss. Use the primitives.

## Common Pitfalls

### Pitfall 1: DispatchSemaphore Deadlocks
**What goes wrong:** App freezes or crashes when using semaphores with async/await
**Why it happens:** Semaphores block threads; Swift Concurrency has limited threads and expects tasks to suspend, not block
**How to avoid:** Never use DispatchSemaphore, DispatchGroup.wait(), or any blocking primitive in async context
**Warning signs:** Tests pass but app hangs under load; random freezes

### Pitfall 2: Continuation Resume Called Multiple Times
**What goes wrong:** Runtime crash with "continuation resumed more than once"
**Why it happens:** NWConnection state handler called multiple times (.ready, then .failed)
**How to avoid:** Use a flag or capture continuation in optional, nil it after first resume
**Warning signs:** Intermittent crashes during connection failures

```swift
// Safe pattern
var continuation: CheckedContinuation<Void, Error>?
connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        continuation?.resume()
        continuation = nil
    case .failed(let error):
        continuation?.resume(throwing: error)
        continuation = nil
    // ...
    }
}
```

### Pitfall 3: Actor Re-entrancy State Corruption
**What goes wrong:** Inconsistent state; duplicate work; missed updates
**Why it happens:** Actor method suspends at await, other calls interleave, state assumed stable isn't
**How to avoid:** Check state after each await; use in-flight task tracking pattern
**Warning signs:** Duplicate network requests; stale data displayed

### Pitfall 4: Stale NWConnection Accumulation
**What goes wrong:** Memory growth; connection limits hit; OS resource exhaustion
**Why it happens:** Connections not explicitly cancelled; relying on deinit that never fires
**How to avoid:** Always call connection.cancel() in finally/defer; implement periodic sweep
**Warning signs:** Increasing memory over time; "too many open files" errors

### Pitfall 5: Timeout Doesn't Actually Cancel Work
**What goes wrong:** Timeout fires but connection keeps trying; resources wasted
**Why it happens:** Cooperative cancellation requires explicit checking
**How to avoid:** Use withTaskCancellationHandler to cancel NWConnection immediately
**Warning signs:** Network activity continues after timeout; late results arrive

### Pitfall 6: NWConnection Never Reaches .ready
**What goes wrong:** Connection hangs forever waiting for .ready state
**Why it happens:** UDP connections may reach .ready immediately or need data exchange; firewall blocks
**How to avoid:** Always have timeout; don't wait indefinitely for state
**Warning signs:** Pings to certain hosts never complete

## Code Examples

Verified patterns from official sources:

### Complete Ping Measurement with Timeout
```swift
// Source: Combined patterns from Apple docs + community best practices
import Network

actor PingService {
    enum PingError: Error {
        case timeout
        case connectionFailed(Error)
        case cancelled
    }

    struct PingResult: Sendable {
        let host: String
        let port: UInt16
        let latency: Duration?
        let error: PingError?

        var isSuccess: Bool { latency != nil && error == nil }
    }

    private let timeout: Duration
    private let queue = DispatchQueue(label: "PingService", qos: .userInitiated)

    init(timeout: Duration = .seconds(3)) {
        self.timeout = timeout
    }

    func ping(host: String, port: UInt16, protocol: NWParameters = .tcp) async -> PingResult {
        let startTime = ContinuousClock.now

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.connect(host: host, port: port, parameters: `protocol`)
                }
                group.addTask {
                    try await Task.sleep(for: self.timeout)
                    throw PingError.timeout
                }

                // First to complete wins, cancel the other
                try await group.next()
                group.cancelAll()
            }

            let elapsed = ContinuousClock.now - startTime
            return PingResult(host: host, port: port, latency: elapsed, error: nil)

        } catch let error as PingError {
            return PingResult(host: host, port: port, latency: nil, error: error)
        } catch is CancellationError {
            return PingResult(host: host, port: port, latency: nil, error: .cancelled)
        } catch {
            return PingResult(host: host, port: port, latency: nil, error: .connectionFailed(error))
        }
    }

    private func connect(host: String, port: UInt16, parameters: NWParameters) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let connection = NWConnection(to: endpoint, using: parameters)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var didResume = false

                connection.stateUpdateHandler = { [weak connection] state in
                    guard !didResume else { return }

                    switch state {
                    case .ready:
                        didResume = true
                        continuation.resume()
                        // Immediately cleanup - we only needed to know it connected
                        connection?.cancel()
                    case .failed(let error):
                        didResume = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        didResume = true
                        continuation.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }

                connection.start(queue: self.queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
```

### Consecutive Failure Tracking (3 failures = host down)
```swift
// Source: User decision - 3 consecutive failures required
actor HostHealthTracker {
    private var consecutiveFailures: [String: Int] = [:]
    private let threshold = 3

    func recordResult(host: String, success: Bool) -> Bool {
        if success {
            consecutiveFailures[host] = 0
            return true // Host is up
        } else {
            let failures = (consecutiveFailures[host] ?? 0) + 1
            consecutiveFailures[host] = failures
            return failures < threshold // Still considered up until threshold
        }
    }

    func isHostDown(_ host: String) -> Bool {
        (consecutiveFailures[host] ?? 0) >= threshold
    }

    func reset(host: String) {
        consecutiveFailures[host] = 0
    }
}
```

### Staggered Ping Scheduling
```swift
// Source: User decision - staggered pings across interval
actor PingScheduler {
    private var pingTask: Task<Void, Never>?

    func startPinging(hosts: [Host], interval: Duration) {
        pingTask?.cancel()

        pingTask = Task {
            while !Task.isCancelled {
                await pingCycleWithStagger(hosts: hosts, interval: interval)
            }
        }
    }

    private func pingCycleWithStagger(hosts: [Host], interval: Duration) async {
        guard !hosts.isEmpty else { return }

        // Distribute pings across the interval
        let staggerDelay = interval / hosts.count

        await withTaskGroup(of: Void.self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    // Stagger start times
                    if index > 0 {
                        try? await Task.sleep(for: staggerDelay * index)
                    }
                    guard !Task.isCancelled else { return }
                    await self.pingService.ping(host: host)
                }
            }
        }
    }

    func stop() {
        pingTask?.cancel()
        pingTask = nil
    }
}
```

### Orphan Connection Sweep
```swift
// Source: User decision - periodic sweep for orphaned connections
actor ConnectionSweeper {
    private var activeConnections: [UUID: (connection: NWConnection, startTime: ContinuousClock.Instant)] = [:]
    private var sweepTask: Task<Void, Never>?
    private let maxAge: Duration = .seconds(30) // Connections older than this are orphaned

    func register(_ connection: NWConnection) -> UUID {
        let id = UUID()
        activeConnections[id] = (connection, .now)
        return id
    }

    func unregister(_ id: UUID) {
        activeConnections.removeValue(forKey: id)
    }

    func startSweeping(interval: Duration = .seconds(10)) {
        sweepTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await sweep()
            }
        }
    }

    private func sweep() {
        let now = ContinuousClock.now
        for (id, entry) in activeConnections {
            if now - entry.startTime > maxAge {
                entry.connection.cancel()
                activeConnections.removeValue(forKey: id)
            }
        }
    }

    func cancelAll() {
        for (_, entry) in activeConnections {
            entry.connection.cancel()
        }
        activeConnections.removeAll()
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DispatchSemaphore for async sync | Swift Concurrency (async/await) | Swift 5.5 (2021) | Eliminates race conditions, deadlocks |
| CFAbsoluteTimeGetCurrent | ContinuousClock | Swift 5.7 (2022) | Type-safe Duration, better semantics |
| Manual timeout timers | Task racing with TaskGroup | Swift 5.5 (2021) | Cleaner cancellation, structured |
| DispatchQueue for thread safety | Actors | Swift 5.5 (2021) | Compile-time isolation checking |
| Completion handlers | withCheckedContinuation | Swift 5.5 (2021) | Bridges callback APIs to async |

**Deprecated/outdated:**
- **DispatchSemaphore with async:** Never worked correctly; causes thread starvation
- **URLSession for TCP latency:** No direct connection-level timing; use NWConnection
- **Date() for timing:** Affected by system clock changes; use ContinuousClock

## Claude's Discretion Recommendations

Based on research, here are recommendations for discretionary items:

### Connection Pooling vs Fresh Connections
**Recommendation: Fresh connections per ping**

Reasoning:
- **Reliability over performance:** Connection pooling introduces staleness risk; stale connections give false positives (connection appears up but is dead)
- **Ping semantics:** A "ping" should measure current connectivity, not cached connection state
- **Cleanup simplicity:** Fresh connections have clear lifecycle (create, use, destroy); pools need health checks
- **Low overhead:** TCP handshake (~1.5 RTT) is acceptable for a ping monitor; we're measuring latency anyway
- **Previous app issue:** Stale connections were a problem; fresh connections avoid this entirely

### Stagger Timing Between Hosts
**Recommendation: Evenly distribute across interval**

Formula: `staggerDelay = interval / hostCount`

Example: 10 hosts with 30-second interval = 3 seconds between each ping start

Reasoning:
- Prevents network/CPU burst at interval start
- Even distribution provides smooth resource usage
- Simple to implement and reason about
- If hosts are added/removed, recalculate

### Orphan Sweep Interval
**Recommendation: 10-second sweep interval with 30-second max age**

Reasoning:
- 10 seconds is frequent enough to catch orphans before they accumulate
- 30-second max age is 10x the 3-second timeout; accounts for slow failures
- Lightweight operation (iterate dictionary, check timestamps)
- Not too aggressive to cause overhead

## Open Questions

Things that couldn't be fully resolved:

1. **UDP "connection" semantics for latency measurement**
   - What we know: UDP is connectionless; NWConnection.ready may occur immediately without network round-trip
   - What's unclear: Whether measuring UDP "connection" time gives meaningful latency
   - Recommendation: For UDP targets, consider sending a small probe packet and waiting for response, or clearly document that UDP latency measures setup overhead only

2. **NWConnection behavior when network changes mid-ping**
   - What we know: Network changes (WiFi to cellular) can affect in-flight connections
   - What's unclear: Exact state transitions and error types
   - Recommendation: Treat any non-.ready/.cancelled final state as failure; timeout will catch hangs

3. **Swift 6 strict concurrency for NWConnection callbacks**
   - What we know: NWConnection callbacks may need @Sendable annotations; closure captures must be Sendable
   - What's unclear: Full compatibility with Swift 6 strict mode without warnings
   - Recommendation: Enable strict concurrency checking early; address warnings as they appear

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation - NWConnection API
- Swift Forums - withCheckedContinuation patterns
- Donny Wals - Task timeout implementation: https://www.donnywals.com/implementing-task-timeout-with-swift-concurrency/
- Simon Whitty swift-timeout: https://github.com/swhitty/swift-timeout
- Swift with Majid - TaskGroups throttling: https://swiftwithmajid.com/2025/02/04/mastering-task-groups-in-swift/
- Swift with Majid - Task Cancellation: https://swiftwithmajid.com/2025/02/11/task-cancellation-in-swift-concurrency/

### Secondary (MEDIUM confidence)
- Jacob's Tech Tavern - Actor Re-entrancy: https://blog.jacobstechtavern.com/p/advanced-swift-actors-re-entrancy
- Swift on Server - Structured Concurrency: https://swiftonserver.com/structured-concurrency-and-shared-state-in-swift/
- Antoine van der Lee - Swift 6.2 Concurrency: https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/
- Swift Forums - Connection pooling discussion: https://forums.swift.org/t/algorithm-for-connection-pooling-with-structured-concurrency/62450

### Tertiary (LOW confidence)
- Various Medium articles on NWConnection latency measurement (patterns verified against official docs)
- Stack Overflow discussions on timeout patterns (cross-referenced with official Swift evolution proposals)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Apple frameworks with official documentation
- Architecture: HIGH - Patterns verified across multiple authoritative sources
- Pitfalls: HIGH - Well-documented issues with Swift Concurrency adoption
- Claude's discretion items: MEDIUM - Based on research but involves judgment calls

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (30 days - stable domain, Swift Concurrency mature)
