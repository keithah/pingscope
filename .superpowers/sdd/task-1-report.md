# Task 1: Durable inbound CloudKit work

## Result

Inbound `CKSyncEngine` record-zone batches are now durably archived in the
boundary's `UserDefaults` suite before they reach the remote receiver. The
receiver is throwing end-to-end, so a history or host-store failure leaves the
batch in the queue. On the next `start()`, queued batches replay before the new
CloudKit fetch; each batch is removed only after a successful apply. A replay
failure propagates from `start()` and is handled by the existing bounded
lifecycle path, while the nonthrowing delegate callback does not spin a retry
loop.

## RED / GREEN evidence

- RED: `swift test --filter CloudSyncCoordinatorTests/testRemoteApplyFailureIsReplayedAfterRestart`
  failed as expected before the durable handoff: the first failed sample write
  left no `PingScope.CloudSync.InboundReplayState.InboundWork` data, and the
  restarted boundary stored zero samples.
- GREEN: the same focused test passes after implementation.
- Focused regression: `swift test --filter CloudSyncCoordinatorTests` passed:
  86 tests, 0 failures.
- Full verification: `swift test` passed:
  992 tests, 0 failures (final clean run).

## Files changed

- `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
  - Added locked, durable inbound batch storage using secure `CKRecord`
    archives plus Codable deletion identities.
  - Changed `RemoteChangeHandler` to `async throws`.
  - Replays queued work before `fetchChanges`, and uses the same configurable
    defaults suite for engine state and inbound work.
- `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
  - Made remote receiver application and the service's testable remote-apply
    entrypoint throw storage failures instead of dropping them with `try?`.
- `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`
  - Added `testRemoteApplyFailureIsReplayedAfterRestart` with a history store
    that fails its first remote upsert and a recreated boundary sharing a
    dedicated defaults suite.
  - Updated direct receiver tests for the throwing contract.

## Self-review

- The batch is committed before receiver invocation and retained on any apply
  or removal error, giving at-least-once replay semantics.
- Replay takes place after engine setup/send but before the first new fetch,
  and checks the existing active-handle lifecycle state before fetching.
- Storage mutations are lock-protected; replay snapshots batches, then removes
  by identifier so an inbound callback that arrives during replay is retained.
- Record archives include system fields, and deletion payloads preserve record,
  zone, owner, and type so replay reconstructs the original operation.
- No probe/network protocols, retention windows, graph/downsampling, or cache
  fingerprint fields were changed.

## Concerns

None. The intended behavior is at-least-once application: if a process dies
after the receiver succeeds but before queue removal, replay may apply the
batch again. Remote sample upserts and host conflict resolution are already
idempotent/retry-safe for that case.

## Review follow-up: account-switch isolation

Review identified that the serialized engine state was cleared on account
change but the adjacent inbound-work archive was not. That could replay a
previous account's records after the new account starts.

- RED: the new account-change test failed before the fix: the inbound archive
  remained (3,662 bytes) after account change and a recreated boundary invoked
  the handler twice rather than once. The startup-replay failure test already
  passed, confirming that a failed replay correctly propagates and preserves
  its queue.
- GREEN: account-change handling now deactivates the current delegate, clears
  both the serialized engine state and inbound-work key in the same isolated
  section, then invokes recovery. A late old-account delegate callback is also
  rejected by the inactive check.
- Added behavioral coverage:
  - `testQueuedInboundWorkIsDiscardedWhenCloudKitAccountChanges`
  - `testReplayFailurePropagatesFromStartAndKeepsInboundWorkQueued`
- Verification after the follow-up:
  - targeted tests: 2 passed
  - `swift test --filter CloudSyncCoordinatorTests`: 88 passed
  - `swift test`: 994 passed

## Re-review follow-up: stale callback admission race

Re-review found a race where an old delegate callback could pass its initial
active check, suspend, then persist work after account-change cleanup.

- RED: `testOldAccountCallbackPausedBeforeAdmissionCannotReplayAfterAccountChange`
  paused exactly after the first active check, changed accounts, resumed, and
  failed before the fix because the recreated boundary invoked the old handler
  once.
- GREEN: inbound work now has a lock-protected account epoch. The callback
  captures that epoch before the injectable admission gate, rechecks active
  state afterward, and conditionally enqueues only when the same epoch is
  still current under the inbound-store lock. Account change increments that
  epoch while clearing the queue, so the resumed old callback neither applies
  nor persists work.
- Verification after the re-review follow-up:
  - focused stale-callback test: 1 passed
  - `swift test --filter CloudSyncCoordinatorTests`: 89 passed
  - `swift test`: 995 passed

## Final review follow-up: commit fencing and persistence failure

- Added an epoch context to remote application. The receiver validates it at
  each storage/host commit point; deterministic gates prove account changes
  reject paused live and startup-replay applies before history mutation.
- Added an internal persistence seam and a controlled boundary failure path:
  enqueue/archive failure deactivates and releases the boundary, cancels work,
  and enters the existing lifecycle handler without invoking the receiver.
- Tests: focused commit-fencing and persistence-failure tests passed;
  `CloudSyncCoordinatorTests` passed on rerun after one pre-existing timing
  assertion flaked; final `swift test` passed 1,000 tests.
