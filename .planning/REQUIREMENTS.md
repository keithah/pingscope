# Requirements

## Core Mac App

- Menu bar shows selected primary host with status color and latency.
- Popover opens quickly and shows host selector, graph, range picker, samples, stats, and status.
- Overlay supports full and compact modes, host selection, settings, close, and graph click to open popover.
- Settings support hosts, display, notifications, history/export, advanced build/runtime controls.
- Default gateway detection works when local-network access is allowed.
- Notification permission can be requested from settings and notification delivery degrades gracefully.

## Probe Behavior

- TCP, UDP, and ICMP probe methods are represented in the domain model.
- TCP performs a fresh connection per measurement.
- UDP performs a fresh datagram send/readiness measurement per sample.
- ICMP is available only in Developer ID/non-sandbox builds where macOS permits it.
- App Store builds hide ICMP and avoid privileged behavior.
- Consecutive failure threshold prevents one transient failure from marking a host down.

## History, Export, Widgets

- Recent in-memory samples power live graphs.
- SQLite history persists samples across restarts.
- Export supports CSV, JSON, and text.
- Widget data sharing is opt-in.
- Widget extension reads shared snapshots and handles stale data.

## Distribution

- `swift build` and `swift test` work outside Xcode.
- Developer ID release produces signed, notarized, stapled DMG.
- Sparkle appcast is generated and uploaded for non-App-Store builds.
- App Store scheme excludes Sparkle and remains sandbox-compliant.
- Release docs and license match the current public release.

## Future iOS Preparation

- `PingScopeCore` stays independent of AppKit/UIKit.
- macOS UI and lifecycle remain isolated in `Sources/PingScopeApp`.
- Future iOS shell can depend on the core without importing macOS-only code.
