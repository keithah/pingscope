# PingScope 0.1.2

Second patch release for the fresh native rebuild, focused on overlay settings reliability, Sparkle feed hosting, widget version consistency, and release validation.

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

## Fixes

- Fixed Display > Overlay settings so Show Overlay, Always on Top, Compact Graph Mode, and Opacity consistently apply to the live overlay window.
- Fixed the overlay window's initial level so the saved Always on Top setting is respected when the overlay is first created.
- Fixed the About checklist overlay action to use the same app delegate bridge as the main settings controls.
- Fixed a macOS reconnect race where a stale scheduler stream could cancel the new scheduler generation after Wi-Fi, hotspot, or VPN changes.
- Default Gateway monitoring now refreshes and resumes probes after network path changes instead of getting stuck at `--ms`.
- Default Gateway endpoint changes clear stale graph and health samples so the popover reflects the active route.
- iOS refreshes the detected Wi-Fi gateway on app launch and path changes.
- iOS Live Activity state now distinguishes continuous monitoring from finite 30-second and 1-minute sessions.
- Added targeted diagnostics for scheduler lifecycle, network status, gateway observations, and probe failures.

## Distribution

- Developer ID DMG is signed, notarized, stapled, and Gatekeeper-verified.
- Sparkle appcast is signed with the PingScope EdDSA key and is now hosted from GitHub Pages.
- Widget extension versions now follow the app's shared marketing version and build number.
- App Store scheme builds from the same codebase without Sparkle or privileged ICMP UI.
- Source is licensed under the GNU Affero General Public License v3.0.
