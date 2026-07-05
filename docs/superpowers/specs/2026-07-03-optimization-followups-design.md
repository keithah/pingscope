# Optimization Followups Design

## Goal

Fix the code-optimizer audit findings without reducing validation coverage, while preserving existing app behavior and keeping each fix independently testable.

## Scope

The implementation covers release and validation script safety, runtime/process resource bounds, history/export memory and observability improvements, UI render/cache reductions, and low-risk algorithmic cleanup. `scripts/validate-ios.sh` keeps the SwiftPM iOS build enabled by default because disabling it would reintroduce a known coverage gap.

## Architecture

Runtime scheduling will keep one logical schedule per measurable host but introduce a scheduler-owned concurrency gate around actual probe measurements. Process execution will keep the existing async API while making timeout cleanup nonblocking and bounding pipe-reader work after output caps.

History/export changes will prefer streaming or smaller-memory paths where callers do not need in-memory exports. SQLite metadata storage will avoid JSON for note-only metadata and keep compatibility with existing rows that already have `metadata_json`.

UI changes will reduce avoidable render-path work by caching derived presentation or moving repeated allocations away from SwiftUI body/Canvas closures. Script changes will use local helpers for path validation, retry, cleanup, and bounded waits.

## Testing

Each behavior change gets a focused failing test or executable script check before implementation. Existing Swift tests remain the broad regression suite. Script changes are verified with `bash -n` and temp-directory smoke checks where external services cannot be called safely.
