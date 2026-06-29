# PingScope 0.2.1

A reliability and polish release. PingScope 0.2.1 focuses on truthful diagnostics, quieter notifications, lower overhead during continuous monitoring, and hardened release tooling. It rolls up the 0.1.4 and 0.1.5 TestFlight builds.

## What's New

- Redesigned notification settings: alert triggers are grouped by category — Availability (host down, recovery), Network path (local network, ISP, internet, remote service), Performance (high latency, internet loss, path degraded), and Network changes — alongside an alert-style preset picker, per-network-status toggles, and a collapsible Advanced thresholds section.
- Quieter by default: noisy network-change and gateway/IP-change notifications are suppressed, and network-change alerts are now opt-in.
- Network diagnosis explains degraded state and reconciles router/gateway, ISP path, and internet endpoints more reliably across Wi-Fi, hotspot, and VPN transitions.
- The popover remembers its all-host selection between sessions.
- Sharper latency graphs in the menu bar app and iOS companion, with reduced redundant rendering work.

## Reliability & Fixes

- Probe latency is now truthful end to end: TCP, UDP, timeout, and Starlink discovery report cancellation honestly instead of masking it as a timeout or false result.
- Batched SQLite history writes with BUSY/LOCKED retry and a cancellable, generation-tracked flush; pending writes are always drained on stop and discarded correctly on reset.
- Fixed `BoundedBuffer` ordering corruption that could occur after the buffer grew past its initial capacity.
- Fixed async process timeout cleanup so timed-out probes release their resources promptly.
- Throttled widget and history refreshes and deduplicated widget publishing by content, reducing background work during long monitoring sessions.
- Added debug log rotation so the diagnostics log no longer grows unbounded.
- Tightened host validation, log redaction, and streaming history exports.

## Under the Hood

- Split large view and settings files into focused per-tab and per-view sources, and kept all Swift sources under 1,000 lines.
- The shared core now compiles cleanly for iOS by gating macOS-only process APIs.
- Expanded test coverage for runtime batching, async process handling, widget snapshots, and history reset behavior.

## Distribution

- App Store build 0.2.1 archives from the same codebase without Sparkle or privileged ICMP UI, for TestFlight and App Store submission.
- The Developer ID release pipeline produces a DMG that is signed, notarized, stapled, and Gatekeeper-verified.
- The Sparkle appcast is signed with the PingScope EdDSA key and hosted from GitHub Pages.
- Release tooling hardened: API-key notarization support for GitHub releases, Xcode Cloud post-clone fixes, automatic version/build derivation from the project, and more robust Sparkle tool discovery.
- Widget extension versions follow the app's shared marketing version and build number.
- Source is licensed under the GNU Affero General Public License v3.0.
