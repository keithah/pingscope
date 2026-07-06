# PingScope 0.3.1

PingScope 0.3.1 is a release polish update for the macOS menu bar latency monitor, with cleaner default monitoring, quieter network alerts, a shareable graph snapshot, and reliability fixes across history, widgets, and runtime persistence.

## What's New

- Default monitoring now includes Cloudflare DNS, Google DNS, and the local default gateway for better internet-path diagnosis.
- Existing installs with the old automatic Cloudflare/default-gateway set are migrated to include Google DNS without resurrecting defaults after user edits.
- Added a share button in the status popover that can generate a graph-focused snapshot for sharing.
- Kept the status popover compact, with the share action next to settings.

## Reliability & Fixes

- Reduced notification spam by coalescing broad internet outage/recovery alerts.
- Improved host persistence and first-run default seeding behavior.
- Hardened history, widget snapshot, graph presentation, and runtime buffering paths.
- Added tests for default host tiers, App Store-safe method normalization, diagnosis confidence, alert coalescing, and legacy default migration.

## Distribution

- Developer ID builds are signed, notarized, stapled, and published through GitHub Releases with a Sparkle appcast.
- App Store builds use the sandboxed `PingScope-AppStore` scheme and exclude ICMP where the App Store sandbox requires it.
- Version: 0.3.1
- Build: 79
