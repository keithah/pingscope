# CloudKit, Gateway, and Digest Reliability Design

## Goal

Make inbound CloudKit changes retryable without losing data, retain the fastest successful default-gateway probe while exposing its provenance, and avoid repeated incident-onset searches without changing diagnosis results.

## Scope and constraints

- This is a stacked follow-up to PR #7 and is based on its head.
- No probe wire-protocol changes, retention changes, graph/downsampling changes, cache-fingerprint changes, or `design/` changes.
- Keep the gateway resolver's fastest-success semantics.
- Keep historical incident output and diagnosis ordering equivalent for equivalent inputs.

## CloudKit remote-change delivery

`CloudSyncRemoteReceiver.apply` will report failure instead of swallowing storage errors. The boundary will use a throwing remote-change callback and retain a durable, replayable inbound work item before acknowledging the callback as successful. A work item contains the received record/deletion batch in a serializable representation, is removed only after `CloudSyncRemoteReceiver` finishes it, and is replayed before a newly started engine fetches more changes.

This separates remote-apply durability from CKSyncEngine's serialized state lifecycle: even if CloudKit advances its in-memory cursor, a locally persisted inbound work item remains available after restart. Applying samples remains idempotent through `upsertRemoteSamples`; host reconciliation continues to use the existing version registry. Failure produces a retryable sync status/log entry and leaves the queued item intact. Retries use the service's existing lifecycle/retry facilities rather than an unbounded delegate task.

## Gateway probe provenance

`DefaultGatewayEndpointResolver` will still race its candidates and return the first successful candidate. Its result will carry an existing host configuration whose method and port identify the actual successful probe. Callers will pass that resolved `HostConfig` through unchanged, and a focused test will force a lower-priority candidate to answer first. No preferred-order waiting or protocol reorder is introduced.

## Incident digest indexing

The onset-diagnosis initializer will build one chronologically sorted sequence per host and maintain per-host cursors as focused-host samples advance. At each failure onset, each cursor is advanced only forward until its timestamp is at or before the onset. The latest known sample is then used for the existing `NetworkPerspectiveDiagnoser` call. This replaces repeated binary searches with a linear pass over each bounded host sequence while preserving the same latest-sample selection rule.

## Testing

- CloudKit: an injected receiver/store failure leaves a durable inbound batch, a later successful start replays it exactly once, and state remains safe across the failure.
- Gateway: a deliberately faster lower-priority candidate is selected and its method/port is preserved.
- History: existing incident cases remain unchanged, plus an interleaved multi-host onset fixture demonstrates cursor-based selection matches the legacy latest-sample semantics.
