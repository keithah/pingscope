# Task 2: Fastest gateway probe provenance

## Result

`DefaultGatewayEndpointResolver` already keeps the fastest-success race and
returns the exact `candidateHost` that produced that successful result. No
production change was needed. The new behavioral coverage verifies that a
lower-priority UDP/53 candidate wins while the higher-priority TCP/80 candidate
is blocked, and that the returned `HostConfig` retains UDP/53 rather than being
reconstructed as the TCP/80 fallback.

## Baseline / already-green evidence

- Added
  `testGatewayResolverReturnsFastestSuccessfulCandidateWithProbeProvenance`.
- The test factory blocks TCP/80 with a cancellable 60-second sleep, returns an
  immediate success for UDP/53, and returns failures for the other candidates.
- Before any production edit, `swift test --filter
  HostTestingTests/testGatewayResolverReturnsFastestSuccessfulCandidateWithProbeProvenance`
  passed: 1 test, 0 failures, in 0.001 seconds.
- Audit finding: `Runtime.swift` constructs one `candidateHost` per task,
  measures it, and returns that same host when its result succeeds. The
  `withTaskGroup` completion order therefore preserves both the fastest winner
  and its method/port provenance.

## GREEN evidence

- `swift test --filter HostTestingTests` passed: 13 tests, 0 failures.
- `swift test` passed: 996 tests, 0 failures.

## Files changed

- `Tests/PingScopeFreshTests/Core/HostTestingTests.swift`
  - Added a regression test for fastest-success gateway resolution preserving
    UDP/53 provenance.
  - Added a test-only probe factory that blocks TCP/80 and immediately succeeds
    for UDP/53.

## Scope review

- `Sources/PingScopeCore/Runtime.swift` was audited but not changed because the
  requested behavior was already present.
- No probe or network wire protocol, retention behavior, graph/downsampling,
  cache fingerprint fields, or `design/` files changed.

## Concerns

None.
