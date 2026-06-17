# PingScope

## Product

PingScope is a native macOS menu bar latency monitor. It shows an iStat-style status item, a focused live graph popover, a compact floating overlay, host management, notifications, durable local history, export, optional widgets, and Sparkle updates for non-App-Store builds.

## Current Release

- Version: `0.1.0`
- Release: https://github.com/keithah/pingscope/releases/tag/v0.1.0
- License: GNU Affero General Public License v3.0
- Distribution:
  - Developer ID DMG through GitHub Releases
  - App Store scheme builds from the same codebase with Sparkle and ICMP hidden

## Architecture

- `Sources/PingScopeCore`: domain, probes, runtime, history, export, widgets snapshot model
- `Sources/PingScopeApp`: macOS AppKit/SwiftUI shell, menu bar, popover, overlay, settings, notifications, updater
- `PingScopeWidget`: WidgetKit extension
- `Tests/PingScopeFreshTests`: current unit and runtime tests
- `scripts`: build, validation, screenshots, appcast, and release automation

## Current Constraints

- macOS 26 / Xcode 26 era APIs
- SwiftPM must continue to build with `swift build`
- Developer ID builds support TCP, UDP, and ICMP where macOS permits it
- App Store builds remain sandbox-compliant and hide privileged ICMP UI
- Widget data sharing stays opt-in to avoid repeated shared-container prompts

## Next Product Direction

1. Clean up the first public release surface.
2. Harden `0.1.x` update flow with Sparkle validation from `0.1.0` to `0.1.1`.
3. Prepare the core for a future iOS companion app without pulling UIKit into the current Mac app prematurely.
