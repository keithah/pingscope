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

## Pending API decision: fail-closed inbound persistence errors

The final review requires a post-start inbound persistence/decoding error to
fail closed, cancel/release/reset the engine, *not* invoke account recovery,
and transition coordinator/service status to a distinct failure with a manual
retry path. The existing `CloudSyncEngineBoundary` contract has only
`start() throws` and an account-change callback. It has no non-account failure
notification after start, so routing this event through the account callback
would create the prohibited automatic restart loop, while handling it only in
the boundary leaves the coordinator/service status stale.

Required minimal API decision before further implementation:

```swift
func setFailureHandler(_ handler: (@Sendable (any Error) async -> Void)?) async
```

`PingScopeCloudSyncCoordinator` would install this handler, set
`status = .failed(...)`, and require an explicit subsequent enable/retry to
call `start()` again. The boundary would use it only for inbound durable-store
failures after cancelling/releasing the engine and clearing serialized state;
it would not use the account-change callback. This is needed to implement and
test the requested production-path status semantics safely.

## Approved repair: terminal persistence failure and account apply drain

### Result

The approved failure API is now part of `CloudSyncEngineBoundary`. The
coordinator installs a generation-matched handler for both initial and
account-recovery engine starts. A post-start inbound persistence failure now
deactivates the delegate, rejects new inbound admission, drains work already
admitted, clears the inbound archive and serialized `CKSyncEngine` state,
cancels/releases the engine, and reports `.failed(...)` without invoking the
account-change recovery path. Requested enable intent remains set, but only a
later explicit `setEnabled(true, ...)` starts another engine and refetches.

Account invalidation no longer invalidates receiver commits by epoch. A small
locked admission/drain coordinator rejects admission after invalidation begins
and waits for every already-admitted live or startup-replay apply to finish.
Only after that drain completes does the boundary clear old-account inbound
work and serialized state and invoke recovery. Admission completion is
idempotent, multiple drain waiters are supported, and cancellation does not
strand a continuation.

Replay decodes the complete durable queue before invoking the receiver, so a
malformed archive cannot partially apply earlier queue entries. Successful
durable admission retains the existing at-least-once behavior: receiver
failure keeps the batch, while successful application removes it.

### RED / GREEN evidence

- RED: `swift test --filter CloudSyncCoordinatorTests/testInboundPersistenceFailureFailsServiceClosedUntilExplicitRetryRefetches`
  failed against the prior account-recovery path: status returned to `.idle`,
  engine creation advanced automatically, the old handle remained active at
  the assertion point, serialized state remained, and the explicit retry did
  not refetch/apply.
- GREEN: the same production-path test passes through the real boundary,
  coordinator, and service. It injects a one-shot inbound persistence failure
  after an account-recovery-created engine, proves zero receiver application,
  `.failed("forcedFailure")`, no automatic third engine, cleared state, and a
  later explicit enable creating/refetching/applying exactly once.
- RED: `swift test --filter CloudSyncCoordinatorTests/testAccountRecoveryWaitsForAdmittedLiveApplyToFinish`
  observed a second engine and completed recovery while the actual receiver
  apply was gated, then rejected the admitted sample.
- GREEN: the same test now holds recovery at one engine until the receiver is
  released, applies the admitted sample, clears the old queue, and only then
  creates the recovery engine.
- RED: `swift test --filter CloudSyncCoordinatorTests/testAccountRecoveryWaitsForAdmittedStartupReplayToFinish`
  likewise created the recovery engine while replay was held and rejected the
  already-admitted replay.
- GREEN: the same test now drains the replay first, records exactly the original
  failed upsert plus one successful replay, clears old work, and creates the
  new-account engine afterward without replaying old work again.
- Additional lifecycle RED/GREEN: extending the persistence test to fail after
  one successful account recovery exposed that the initially installed failure
  closure was stale (`.idle`, no explicit-refetch apply). Reinstalling the
  handler with the recovery generation made the extended test pass.

### Timing-flake repair

The prior report did not name the broader-suite account-switch assertion. The
shared helper used by
`testDelegateAccountSwitchEventDefersCancellationAndFullyRetiresBoundary` and
`testDelegateSignOutEventDefersCancellationAndFullyRetiresBoundary` contained
a concrete race: it waited for host-handle release, then immediately asserted
the coordinator's later `.accountUnavailable` publication. The helper now
uses continuation-backed gates for cancellation start and delegate-callback
return, and awaits the semantic terminal coordinator status before inspecting
the released handle and delegate. Both focused tests pass with that ordering,
and the complete coordinator suite passed on the first final run.

### Files changed

- `Sources/PingScopeCloudSync/PingScopeCloudSyncCoordinator.swift`
  - Added the minimal `setFailureHandler` boundary API and default no-op.
  - Installed generation-matched failure handlers for initial and recovered
    engines, preserved enable intent, and published terminal `.failed` state.
  - Cleared both boundary callbacks on definitive disable.
- `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
  - Replaced account-epoch commit fencing with the admission/drain coordinator.
  - Added fail-closed persistence retirement/reset and distinct failure
    notification without account recovery.
  - Predecoded replay batches before receiver invocation and retained
    receiver-failure replay semantics.
- `Sources/PingScopeCloudSync/PingScopeCloudSyncService.swift`
  - Made an explicit enable from terminal coordinator failure retire the stale
    local drain state and call the coordinator retry path.
- `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`
  - Added production-path persistence failure/manual refetch coverage.
  - Replaced epoch-rejection expectations with deterministic live/replay drain
    tests gated inside the actual receiver apply.
  - Stabilized the shared delegate account-loss/account-switch helper.

### Verification

- Focused reliability group: 4 tests passed, 0 failures.
- `swift test --filter CloudSyncCoordinatorTests`: 92 tests passed, 0 failures.
- `swift test`: 1,000 tests passed, 0 failures.

### Self-review

- Durable storage failures never invoke the account-change callback, so they
  cannot enter the automatic recovery loop.
- The terminal-failure marker is published before an admission releases drain
  waiters, preventing a simultaneous account event from racing into recovery.
- Once invalidation closes admission, late callbacks cannot enter the old or
  new session; admitted work owns a context that remains valid until its apply
  and durable queue removal finish.
- Recovery does not clear the inbound queue or serialized state until the
  admitted count reaches zero. Live and replay tests both exercise the
  in-flight-after-admission path.
- Failure reset clears the serialized state before the handler runs, so an
  explicit retry creates from no cursor and refetches.
- No probe/wire protocol, retention, graph/downsampling, or cache-fingerprint
  code changed.

### Concerns

No unresolved concerns. The intentional at-least-once tradeoff remains: a
process death after receiver success but before queue removal may reapply an
idempotent batch.
