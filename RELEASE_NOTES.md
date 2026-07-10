# PingScope 0.4.0

PingScope 0.4.0 is a cross-platform redesign of the macOS and iOS monitoring experience. Signal puts the live graph first, Ring provides an alternate health-focused view, and both platforms now make host and session controls easier to reach without changing the monitoring engine.

## What's New

- Redesigned the iOS app around Monitor, Hosts, and History tabs with a floating tab bar, host switcher, host editor, drag-to-reorder, and clearer session controls.
- Added the Signal graph-first display and Ring health display on both macOS and iOS, with Signal as the default.
- Reworked the macOS popover with a larger live graph, compact stats, per-host sparklines, an All Hosts comparison view, and a directly accessible ping-interval picker.
- Made the macOS floating overlay resizable, with independent compact/expanded sizing and Signal/Ring display choices.
- Smoothed latency graphs and sparklines across the macOS app, iOS app, overlay, and widgets using a shared Catmull-Rom curve implementation.
- Added Current, Light, and Dark appearance choices to shared graph exports.

## Reliability & Fixes

- Fixed the iOS cold-launch race so continuous monitoring reliably starts when the app becomes active.
- Preserved explicit Live, 30-second, 1-minute, and Stop choices when the startup backstop runs.
- Fixed mixed All Hosts ping intervals so the popover reports the mixed state and can apply a selected interval to every enabled host.
- Kept All Hosts on the multi-line Signal graph because a single Ring cannot represent multiple hosts.
- Added focused coverage for graph geometry, display persistence, run controls, host ordering, overlay defaults, and startup coordination.

## Distribution

- Developer ID builds are signed, notarized, stapled, and published through GitHub Releases with a Sparkle appcast.
- App Store builds use the sandboxed `PingScope-AppStore` scheme and remain Sparkle-free.
- The iOS build is distributed through TestFlight before App Store review.
- Version: 0.4.0
- Build: 80
