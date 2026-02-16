# Phase 10: True ICMP Support - Research

**Researched:** 2026-02-16
**Domain:** macOS ICMP networking, sandbox detection, non-privileged socket programming
**Confidence:** HIGH

## Summary

This phase implements true ICMP ping capability for the non-sandboxed Developer ID distribution, with automatic detection and graceful hiding when running in the App Store sandbox. Research confirms that macOS provides a **non-privileged ICMP socket mechanism** using `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` that allows ICMP echo requests without root privileges. This is the approach used by Apple's SimplePing sample and derivative libraries like SwiftyPing.

The key technical insight is that on Apple platforms, you can open a special, non-privileged ICMP datagram socket (not raw socket) to send and receive pings. This eliminates the need for root privileges or setuid binaries, but **requires** the application to be running outside the App Store sandbox.

Sandbox detection can be reliably performed at runtime by checking for the `com.apple.security.app-sandbox` entitlement using Security framework APIs or by checking if the home directory contains `/Library/Containers/`.

**Primary recommendation:** Build an ICMPPinger service using SOCK_DGRAM + IPPROTO_ICMP sockets, wrap with Swift Concurrency via `withCheckedThrowingContinuation`, add a `.icmp` case to PingMethod, and conditionally expose the option in UI based on runtime sandbox detection.

## Standard Stack

The established libraries/tools for this domain:

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Darwin sockets | N/A | SOCK_DGRAM + IPPROTO_ICMP | Apple's blessed non-privileged ICMP mechanism |
| CFSocket | N/A | RunLoop integration for async I/O | Standard Apple approach for socket events |
| Security.framework | N/A | Sandbox status detection | SecCodeCopySigningInformation for entitlement check |
| Swift Concurrency | Swift 5.9+ | async/await wrapping | Project standard per STATE.md decisions |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| ContinuousClock | High-precision latency timing | Same as existing PingService |
| withCheckedThrowingContinuation | Bridge callback to async | Wrap socket callbacks for Swift Concurrency |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom ICMP implementation | SwiftyPing library | External dependency violates "no external dependencies" constraint |
| CFSocket | GCD dispatch sources | CFSocket more compatible with existing SimplePing patterns |
| Runtime sandbox check | Compile-time #if | Runtime allows single binary for both distributions |

**No Installation Required:** This implementation uses only system frameworks.

## Architecture Patterns

### Recommended Project Structure

```
Sources/PingScope/
├── Services/
│   ├── PingService.swift          # Existing - add .icmp case routing
│   ├── ICMPPinger.swift           # NEW - ICMP socket implementation
│   └── SandboxDetector.swift      # NEW - Runtime sandbox detection
├── Models/
│   └── PingMethod.swift           # Add .icmp case
├── Views/
│   └── AddHostSheet.swift         # Filter PingMethod picker based on sandbox
└── Utilities/
    └── ICMPPacket.swift           # ICMP header/checksum structures
```

### Pattern 1: Non-Privileged ICMP Socket

**What:** Use SOCK_DGRAM instead of SOCK_RAW for ICMP
**When to use:** Always on macOS for non-sandboxed ICMP ping
**Example:**
```swift
// Source: Apple Developer Forums + macOS icmp(4) man page
let socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
// No root privileges required!
// Kernel handles IP header construction
// Only ICMP echo request/reply types permitted
```

### Pattern 2: Sandbox Detection via Environment

**What:** Check home directory path for sandbox indicator
**When to use:** Fast, simple runtime check with no Security framework overhead
**Example:**
```swift
// Source: Apple Developer Forums thread/62939
enum SandboxDetector {
    static var isRunningInSandbox: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }
}
```

### Pattern 3: Async/Await Socket Wrapping

**What:** Bridge CFSocket callback to Swift Concurrency
**When to use:** Integrate ICMP responses with project's async patterns
**Example:**
```swift
// Source: Swift Concurrency documentation
func measureICMPLatency(to host: String, timeout: Duration) async throws -> Duration {
    try await withCheckedThrowingContinuation { continuation in
        // Set up CFSocket with callback that calls continuation.resume()
        // Must call resume exactly once
    }
}
```

### Pattern 4: Conditional UI Based on Capabilities

**What:** Filter available PingMethod options at runtime
**When to use:** Hide .icmp when sandboxed
**Example:**
```swift
// In AddHostSheet
Picker("Ping Method", selection: $viewModel.pingMethod) {
    ForEach(PingMethod.availableCases, id: \.self) { method in
        Text(method.displayName).tag(method)
    }
}

// In PingMethod
static var availableCases: [PingMethod] {
    if SandboxDetector.isRunningInSandbox {
        return [.tcp, .udp, .icmpSimulated]
    }
    return allCases // includes .icmp
}
```

### Anti-Patterns to Avoid

- **Using SOCK_RAW:** Requires root privileges; use SOCK_DGRAM instead
- **Blocking socket calls on main thread:** Always use async dispatch
- **Hardcoding sandbox status:** Must detect at runtime for dual-distribution
- **Multiple continuation resumes:** Will crash; ensure exactly-once semantics
- **External dependencies:** Project constraint prohibits SwiftyPing/SimplePing packages

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICMP checksum | Manual byte calculation | Standard internet checksum algorithm | Must be ones-complement correctly |
| Socket run loop integration | Raw fd polling | CFSocket with RunLoopSource | Apple's blessed async socket pattern |
| Sandbox detection | File system probing | NSHomeDirectory() path check | Simple, reliable, no permissions needed |
| Timeout racing | Manual timer management | withThrowingTaskGroup | Project already uses this pattern |

**Key insight:** The ICMP packet structure is well-defined (8-byte header + payload). Copy the checksum algorithm from Apple's SimplePing - it's the same algorithm used since BSD networking.

## Common Pitfalls

### Pitfall 1: Using Raw Sockets

**What goes wrong:** Socket creation fails with "Operation not permitted"
**Why it happens:** SOCK_RAW requires root privileges on macOS
**How to avoid:** Use `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` instead
**Warning signs:** EPERM error on socket() call

### Pitfall 2: Continuation Resume Violations

**What goes wrong:** App crashes or hangs forever
**Why it happens:** withCheckedContinuation must be resumed exactly once
**How to avoid:** Use defer blocks, careful timeout handling, track resume state
**Warning signs:** Intermittent crashes, requests that never complete

### Pitfall 3: Sandbox Detection False Positives

**What goes wrong:** ICMP option shown when sandboxed, then fails
**Why it happens:** Incomplete sandbox detection logic
**How to avoid:** Test detection on both sandboxed and non-sandboxed builds
**Warning signs:** Users report "ICMP doesn't work" on App Store version

### Pitfall 4: ICMP Identifier Mismatch

**What goes wrong:** Responses from other ping processes are incorrectly matched
**Why it happens:** ICMP identifier not verified on response
**How to avoid:** Generate unique identifier per pinger, validate on receive
**Warning signs:** Incorrect latency measurements, responses for wrong hosts

### Pitfall 5: IPv6 Echo Handling

**What goes wrong:** IPv6 pings receive their own sent packet
**Why it happens:** macOS ICMPv6 sockets echo sent messages back
**How to avoid:** Filter received packets by checking if source matches destination
**Warning signs:** Immediate "responses" with ~0ms latency to IPv6 hosts

### Pitfall 6: Byte Order Issues

**What goes wrong:** Checksum fails, packet rejected
**Why it happens:** Network byte order (big-endian) vs host byte order confusion
**How to avoid:** Use htons/ntohs for 16-bit fields, htonl/ntohl for 32-bit
**Warning signs:** Ping never receives response, tcpdump shows malformed packets

## Code Examples

Verified patterns from official sources and established implementations:

### ICMP Header Structure

```swift
// Source: macOS icmp(4) man page + SwiftyPing
struct ICMPHeader {
    var type: UInt8        // 8 = echo request, 0 = echo reply
    var code: UInt8        // Must be 0 for echo
    var checksum: UInt16   // Internet checksum
    var identifier: UInt16 // Process-unique identifier
    var sequenceNumber: UInt16 // Incremented per request
}

// Echo request type constants
let ICMP_ECHO_REQUEST: UInt8 = 8
let ICMP_ECHO_REPLY: UInt8 = 0
```

### Internet Checksum Calculation

```swift
// Source: Apple SimplePing / RFC 1071
func icmpChecksum(data: Data) -> UInt16 {
    var sum: UInt32 = 0
    var index = 0

    // Sum 16-bit words
    while index < data.count - 1 {
        let word = UInt32(data[index]) << 8 | UInt32(data[index + 1])
        sum += word
        index += 2
    }

    // Add odd byte if present
    if index < data.count {
        sum += UInt32(data[index]) << 8
    }

    // Fold 32-bit sum to 16 bits
    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }

    return ~UInt16(sum)
}
```

### Socket Creation (Non-Privileged)

```swift
// Source: macOS icmp(4) man page
func createICMPSocket() throws -> Int32 {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    guard fd >= 0 else {
        throw PingError.connectionFailed("Failed to create ICMP socket: \(errno)")
    }

    // Disable SIGPIPE for broken connections
    var noSigPipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    return fd
}
```

### Sandbox Detection

```swift
// Source: Apple Developer Forums thread/62939
enum SandboxDetector {
    /// Returns true if the app is running in the App Store sandbox
    static var isRunningInSandbox: Bool {
        // App Store sandbox places app container in /Library/Containers/
        NSHomeDirectory().contains("/Library/Containers/")
    }
}
```

### Async Wrapper Pattern

```swift
// Source: Swift Concurrency patterns + project conventions
func ping(host: String, timeout: Duration) async throws -> Duration {
    try await withThrowingTaskGroup(of: Duration.self) { group in
        group.addTask {
            try await self.sendAndReceiveICMP(to: host)
        }

        group.addTask {
            try await Task.sleep(for: timeout)
            throw PingError.timeout
        }

        defer { group.cancelAll() }

        guard let result = try await group.next() else {
            throw PingError.cancelled
        }
        return result
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SOCK_RAW + setuid | SOCK_DGRAM + IPPROTO_ICMP | macOS 10.x | No root required |
| GCD semaphores | Swift Concurrency | Project decision | Eliminated race conditions |
| Callback-based | withCheckedContinuation | Swift 5.5+ | Cleaner async code |
| SimplePing Obj-C | Pure Swift implementation | 2020s | Type safety, no bridging |

**Deprecated/outdated:**
- Using SOCK_RAW for ICMP: Requires root, use datagram sockets instead
- GCD-based timeout handling: Project uses withThrowingTaskGroup per STATE.md decisions
- External SimplePing/SwiftyPing dependencies: Not allowed per project constraints

## Open Questions

Things that couldn't be fully resolved:

1. **CFSocket vs GCD Dispatch Source**
   - What we know: Both work for socket async I/O; CFSocket is more commonly used in ping implementations
   - What's unclear: Which integrates better with Swift Concurrency continuation patterns
   - Recommendation: Start with CFSocket (matches SimplePing pattern), refactor to dispatch source if needed

2. **IPv6 Support Scope**
   - What we know: ICMPv6 requires different socket setup (AF_INET6, IPPROTO_ICMPV6)
   - What's unclear: Whether IPv6 ICMP is required for this phase
   - Recommendation: Implement IPv4 first, add IPv6 in follow-up if needed (most hosts are reachable via IPv4)

3. **Error Handling Granularity**
   - What we know: Multiple failure modes (network unreachable, host unreachable, timeout)
   - What's unclear: How much detail to expose to users vs internal logging
   - Recommendation: Map to existing PingError cases, add ICMP-specific subcases if user-visible

## Sources

### Primary (HIGH confidence)

- macOS icmp(4) man page - Socket types, privilege model, message type restrictions
- Apple Developer Forums thread/62939 - Sandbox detection via NSHomeDirectory()
- Apple Developer Forums thread/744172 - ICMP implementation guidance
- SwiftyPing source code - Socket creation pattern: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`

### Secondary (MEDIUM confidence)

- [Patrick Ekman: ICMP Sockets](https://ekman.cx/articles/icmp_sockets/) - macOS SOCK_DGRAM details
- [SimplePing GitHub](https://github.com/robertmryan/SimplePing) - Non-privileged socket approach
- Swift Concurrency documentation - withCheckedContinuation patterns

### Tertiary (LOW confidence)

- General WebSearch results on ICMP implementations - used for ecosystem discovery only

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - Based on official Apple documentation and verified open-source implementations
- Architecture: HIGH - Aligns with existing project patterns (Swift Concurrency, actor isolation)
- Pitfalls: HIGH - Well-documented issues from multiple sources and Apple forums
- Sandbox detection: HIGH - Official Apple forums discussion, simple verifiable approach

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (stable domain, 30 days)
