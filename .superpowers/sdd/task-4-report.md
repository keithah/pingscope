# Task 4 Report: Additive ActivityKit Payload

## Implemented

- Added platform-neutral `PingScopeLiveActivityMode` and bounded
  `PingScopeLiveActivityHostRow` payload models without importing SwiftUI.
- Extended `ContentState` with defaulted `mode` and `hostRows` fields while
  retaining every pre-existing scalar property and initializer parameter.
- Added custom decoding that defaults absent legacy `mode` and `hostRows` keys
  to `.focused` and `[]`; encoding writes the new keys additively.
- Limited activity state construction to three rows and each row to twelve
  reduced latency samples.
- Kept `ActivityAttributes` conformance conditional on iOS so the Codable
  model can be tested by the macOS Swift package suite.

## TDD Evidence

1. Added `PingScopeLiveActivityTests` before production changes.
2. `swift test --filter PingScopeLiveActivityTests` initially failed because
   the ActivityKit model and new payload symbols were unavailable to the test
   target.
3. Implemented the minimal payload and compatibility decoding, then reran the
   focused suite successfully.

## Verification

- `swift test --filter PingScopeLiveActivityTests`: 5 passed.
- `swift test`: passed.
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`: `BUILD SUCCEEDED`.
- `git diff --check`: passed.

## Self-Review

No defects found. The old scalar-only decode fixture verifies the compatibility
path, while focused and All Hosts round trips, 3-row/12-sample caps, and the
under-4096-byte maximum payload fixture cover the new contract.

## Payload-Bound Follow-Up

**Payload fix commit:** `aed51d9` (`Bound Live Activity row payloads`)

- Made `ContentState.hostRows` and `PingScopeLiveActivityHostRow.samples`
  immutable after initialization.
- Added deterministic, Unicode-safe host-string limits: display names allow at
  most 24 characters / 72 UTF-8 bytes; endpoint captions allow at most 48
  characters / 144 UTF-8 bytes.
- Applied the same bounds through normal construction and custom decoding.
- Added oversized row, sample, and multi-byte grapheme tests that assert the
  exact stored truncation and an encoded `ContentState` below 4,096 bytes.

**Results:**

- `swift test --filter PingScopeLiveActivityTests`: 7 passed.
- `swift test`: passed.
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`: `BUILD SUCCEEDED`.
