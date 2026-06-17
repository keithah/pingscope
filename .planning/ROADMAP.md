# PingScope Roadmap

## Shipped

### 0.1.0 - Fresh Mac Rebuild

Status: shipped
Tag: `v0.1.0`

Delivered:

- iStat-style menu bar indicator.
- Live popover with range picker, latency graph, axis labels, samples, packet loss, and min/avg/max.
- Floating overlay with full and compact modes, right-click actions, host selector, settings, close, and graph-to-popover interaction.
- Host management with default gateway detection, TCP/UDP/Developer ID ICMP support, thresholds, enabled state, and notification policy.
- Settings tabs for Hosts, Display, Notifications, History, and Advanced.
- Durable SQLite history and CSV/JSON/text export.
- WidgetKit extension backed by opt-in shared data.
- Sparkle appcast for non-App-Store builds.
- Developer ID signing, notarization, stapling, and GitHub release automation.
- App Store build path that excludes Sparkle and hides privileged ICMP options.
- AGPLv3 licensing.

## Current Cleanup

- [x] Remove old implementation files and tests from the prior app.
- [x] Remove old App Store screenshots/metadata and duplicate widget target.
- [x] Replace legacy planning history with this current roadmap.
- [x] Rebuild and re-upload `0.1.0` assets after cleanup so the release source archive and binary artifacts line up.
- [ ] Manually install the GitHub DMG on a clean account and verify first-run behavior.

## 0.1.1 - First Patch

Goal: validate the public update path and close first-release polish items.

- [ ] Publish a signed/notarized `0.1.1` DMG through the same release script.
- [ ] Verify Sparkle update from `0.1.0` to `0.1.1`.
- [ ] Refresh release screenshots if UI changes.
- [ ] Run manual widget gallery placement QA.
- [ ] Validate default gateway behavior on Wi-Fi, Ethernet, and hotspot.

## 0.2.0 - Mac Polish

Goal: improve confidence and daily usability without expanding platform scope.

- [ ] Add richer release smoke automation around overlay/context-menu interactions.
- [ ] Add explicit diagnostics view or log export for probe failures.
- [ ] Improve widget visual polish after real use.
- [ ] Review menu bar and overlay behavior across Spaces/full-screen apps.

## 0.3.0 - iOS Preparation

Goal: prepare the codebase for a future iOS companion app.

- [ ] Audit `PingScopeCore` for platform-neutral APIs.
- [ ] Keep macOS-only code isolated in `Sources/PingScopeApp`.
- [ ] Add compile-only iOS shell target that depends on `PingScopeCore`.
- [ ] Define iOS monitoring constraints around background execution, notifications, and widgets.

## Later

- iOS companion app.
- App Store submission automation if App Store distribution becomes a priority.
- Longer-term history views and pruning controls.
- More advanced export/reporting only if users ask for it.
