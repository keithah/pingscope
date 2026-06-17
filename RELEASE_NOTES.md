# PingScope 0.1.0

Fresh native macOS rebuild focused on a quiet, iStat-style latency monitor.

## Highlights

- iStat-style menu bar indicator with status dot and latency readout.
- Live popover with host selector, graph, samples, packet loss, and min/avg/max stats.
- Floating overlay with full and compact modes, right-click host selection, settings, popover, and close actions.
- TCP, UDP, and Developer ID ICMP probe support, with ICMP hidden from App Store builds.
- Default gateway detection and local-network monitoring controls.
- Host management, thresholds, notification policies, and start-at-login support.
- Durable local history with CSV, JSON, and text export.
- Optional widget data sharing, disabled by default to avoid repeated shared-container prompts.
- Sparkle updater support for non-App-Store builds.

## Distribution

- Developer ID DMG is signed, notarized, stapled, and Gatekeeper-verified.
- Sparkle appcast is signed with the PingScope EdDSA key.
- App Store scheme builds from the same codebase without Sparkle or privileged ICMP UI.
- Source is licensed under the GNU Affero General Public License v3.0.
