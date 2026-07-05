# PingScope 0.3.1

PingScope 0.3.1 is a macOS-focused release that tightens the monitoring UI, fixes stale Starlink discovery behavior, expands history export, and prepares the App Store/TestFlight path for the next round of review.

## What's New

- Refreshed the About pane with the product page link, software update action, and privacy information in one place.
- Removed the always-visible first-run checklist from About; only required setup issues are surfaced when they need attention.
- History export now defaults to 1 hour, adds Max for the full retained 7-day history window, and supports custom hour/day ranges capped by retention.
- Updated the product page assets and copy with current macOS screenshots, overlay imagery, dynamic GitHub download links, and support email flow.
- Added iOS companion positioning on the product page while keeping the shipping app experience macOS-first.

## Reliability & Fixes

- Fixed stale Starlink hosts remaining visible on non-Starlink networks when discovery misses because the dish endpoint is unavailable.
- Preserved host persistence after primary-host selection, including after a decode failure recovery path.
- Reduced background work in graph, widget, history, and diagnostics paths.
- Hardened history export streaming and validation for larger retained-history exports.
- Fixed a launch/restart race where the selected host could stop receiving fresh samples after the measurement stream was restarted.
- Improved release, notarization, Xcode build, simulator smoke, and GitHub Pages publishing scripts.

## Distribution

- Developer ID builds are signed, notarized, stapled, and published through GitHub Releases with a Sparkle appcast.
- App Store builds use the sandboxed `PingScope-AppStore` scheme and remain Sparkle-free.
- Xcode Cloud should archive `PingScope-AppStore` for TestFlight and App Store submission from this versioned commit.
- Version: 0.3.1
- Build: 66
