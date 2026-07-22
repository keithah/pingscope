# PingScope 0.5.1 Review Corrections Plan

> Execute this plan test-first on `codex/ios-all-hosts-live-activity`. Every RED must compile and fail an assertion through a real coordinator, provider, or lifecycle integration seam.

## Baseline and safety

- Preserve `design/` and all protocol, retention, downsampling, and cache-fingerprint behavior.
- Keep every commit local and append `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Do not push, tag, upload, notarize, or post externally.
- Baseline evidence: `swift test` at `4a7aba5` executes 808 tests with 0 failures.
- Phase-0 evidence: simulator crash report `PingScope-2026-07-19-154712.ips` shows an uncaught Objective-C exception (`SIGABRT`, `objc_exception_throw`) from `DefaultCloudKitContainerProvider.defaultContainer()`.

## Slice 1: CloudKit activation and availability

Files:
- Modify `Sources/PingScopeCloudSync/PingScopeCloudSyncActivationController.swift`
- Modify `Sources/PingScopeCloudSync/CKSyncEngineBoundary.swift`
- Modify `Sources/PingScopeApp/PingScopeModel.swift`
- Modify `Tests/PingScopeFreshTests/Cloud/CloudSyncCoordinatorTests.swift`
- Add or modify macOS model integration tests under `Tests/PingScopeFreshTests/MacApp/`

Behavioral tests first:
1. Leave defaults in the exact state produced by process death after a pre-armed startup attempt; a new controller must consume that attempt and disable preference at the configured threshold without calling enable again.
2. Drive `activatePersisted` through N-1 failing service starts and verify preference remains enabled and subsequent controllers retry; the Nth failure disables preference; a successful start resets the persisted count.
3. Suspend an automatic enable in the fake service, issue a user disable, then release the first call; verify no automatic-failure state is written.
4. Inject a CloudKit account provider reporting `.available` while its legacy ubiquity token signal is nil; verify account availability and start proceed.
5. Drive the macOS model’s persisted activation path through a failing service and verify guarded parking semantics.

Implementation:
- Pre-arm and synchronously persist the automatic attempt before crossing into CloudKit; clear only after confirmed success.
- Track an activation generation so superseded automatic work cannot mutate defaults.
- Keep automatic preference enabled below threshold and disable only at threshold; user-initiated failures remain visible without creating a startup loop.
- Detect the iCloud-container entitlement before constructing `CKContainer`, then call `accountStatus()` as the account gate; do not use `ubiquityIdentityToken`.
- Route macOS startup/user changes through the same activation controller.

Verification:
`swift test --filter 'CloudSync|Mac.*Cloud'`

## Slice 2: Multi-host session ownership

Files:
- Modify `Sources/PingScopeiOS/PingScopeIOSMultiHostSessionCoordinator.swift`
- Modify `Sources/PingScopeiOS/PingScopeIOSApp.swift`
- Modify coordinator integration tests in `Tests/PingScopeFreshTests/iOS/`

Behavioral tests first:
1. Ingest samples, focus a host, explicitly stop through the coordinator, restart, and verify all current series are empty.
2. Suspend all-host state, remove a host, restore all-host scope, and verify removed series never returns.
3. Stop/start without prior scope suspension and verify no preserved samples are merged.

Implementation:
- Give explicit stop an unconditional reset of suspension and preserved series.
- Preserve only active-session scope transitions; prune preservation against current hosts.
- Introduce `.scopeSuspended` so scope changes are not recorded as user stops.

Verification:
`swift test --filter 'MultiHost.*Session|Scope'`

## Slice 3: Live Activity lifecycle integration

Files:
- Modify `Sources/PingScopeiOS/PingScopeIOSLifecycleOrchestration.swift`
- Modify `Sources/PingScopeiOS/PingScopeIOSApp.swift`
- Modify `Tests/PingScopeFreshTests/iOS/LiveMonitorSessionControllerTests.swift`

Behavioral tests first, using a fake activity directory/driver through one stateful lifecycle orchestrator:
1. Keep-alive expiration continues monitoring and emits rolling live updates with `staleDate = now + interval`.
2. Non-keep-alive expiration records the paused/stale update before simulated slow persistence and never ends the activity.
3. Foreground after pause updates the same activity ID; if that activity becomes defunct before resume, the orchestrator requests a replacement.
4. Foreground racing expiration converges on one active activity without ending a resumed activity.
5. Explicit stop and finite completion end; background expiration does not.

Implementation:
- Put the activity driver behind the lifecycle orchestrator and use it from shipping app paths.
- Release defunct references before deciding resume and fall back to request when update loses its reference.
- Publish the paused update before snapshot/history work.
- Roll stale dates for continuous background keep-alive updates.
- Route stop/finite completion through the end decision or delete the unused abstraction.

Verification:
`swift test --filter 'LiveActivity|BackgroundRuntime'`

## Slice 4: Cellular diagnosis and identity palette

Files:
- Modify `Sources/PingScopeCore/NetworkPerspectiveDiagnosis.swift`
- Modify iOS diagnosis integration code where current path/interface is supplied
- Modify `Sources/PingScopeiOS/PingScopeIOSGraphViews.swift`
- Modify `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Modify `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify diagnosis and presentation tests

Behavioral tests first:
- Cellular plus LAN-scoped host is suppressed; degraded upstream remains; nil interface fails open; mixed recent interfaces do not classify as cellular; gateway-only cellular input yields no misleading empty-measurements diagnosis.
- Render inputs for one host resolve the same shared identity palette value in graph and ring, and presentation palette count equals that source.

Implementation:
- Filter cellular-inapplicable LAN hosts before diagnosis/confidence derivation.
- Derive interface from current path when present, otherwise require agreement across a recent sample window.
- Hoist one shared host identity palette and derive all counts/lookups from it.

Verification:
`swift test --filter 'NetworkPerspective|Palette|ConcentricRing'`

## Slice 5: History map and widget correctness

Files:
- Modify `Sources/PingScopeiOS/PingScopeIOSHistoryContainerDecision.swift`
- Modify `PingScope/PingScopeIOSHistoryMapView.swift`
- Modify `Sources/PingScopeExtensionSupport/WidgetTimelineSupport.swift`
- Modify widget target mapping code
- Modify history-map and extension-support tests

Behavioral tests first:
- Build the resolved history presentation with nonzero located samples and verify the real container omits the empty card; verify range-empty copy says “in this range”, while globally empty says “yet”.
- Drive shared widget entry mapping at exactly 15 minutes, future-generated clock skew, generated time beyond horizon, and nil content time; verify provider entries use the same mapping and schedule.

Implementation:
- Carry authorization, opt-in, and global located count through resolved history presentation into the container/view.
- Move freshness and entry mapping into `PingScopeExtensionSupport`; alias widget stale interval and relevance to `WidgetTimelineSchedule.staleInterval`.

Verification:
`swift test --filter 'HistoryMap|WidgetTimeline'`

## Slice 6: Low-risk ring polish

Files:
- Modify `Sources/PingScopeiOS/PingScopeIOSRingViews.swift`
- Modify `Sources/PingScopeiOS/PingScopeIOSMultiHostPresentation.swift`
- Modify concentric ring presentation tests

Behavioral tests first:
- Down and near-zero healthy render inputs differ in status treatment.
- Computed container extent contains the outer ring at supported Dynamic Type scale.
- “+K more” exposes a focus/expand action naming the hidden count.
- Concentric ring memo builds once for identical inputs and invalidates on meaningful input.

Implementation:
- Encode status separately from identity color, size from computed extent with scaled metrics, make overflow actionable, and remove the obsolete grid memo.

Verification:
`swift test --filter 'ConcentricRing'`

## Final verification and simulator evidence

Run serially:
1. `swift build`
2. `swift test`
3. `xcodebuild -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build`
4. `xcodebuild -scheme PingScope-DeveloperID -destination 'generic/platform=macOS' build` (clean DerivedData and retry once only for `database is locked`)
5. `which rg && scripts/validate-ios.sh`
6. `scripts/validate-app-smoke.sh`
7. `git diff --check`
8. `git status --short -- design`

Simulator scenarios:
- Broken entitlement: enable sync, confirm guarded disable, terminate/relaunch, confirm clean launch and persisted guard state.
- Available CloudKit account with iCloud Drive signal absent: confirm activation remains enabled using the injectable account seam; simulator account limitations must be reported explicitly.
- Start monitoring, background past expiration, record activity ID, foreground, and confirm the retained activity ID resumes.

Report findings first, exact behavioral RED and GREEN commands/results, replacements of helper-only tests, commit hashes/files, totals, skipped risks, proposed 0.5.1 build 90, untouched `design/`, and no publication.
