# Phase 2: Menu Bar & State - Research

**Researched:** 2026-02-14
**Domain:** macOS status bar interactions (AppKit + SwiftUI bridge)
**Discovery level:** 1 (quick verification)
**Confidence:** HIGH

## Summary

Phase 2 can be implemented with built-in macOS APIs only; no new package dependencies are needed. The stable pattern is `NSStatusItem` + `NSPopover` + `NSMenu`, with event routing handled by a custom status-bar button target action. Use `PingScheduler` callbacks to drive `@MainActor` menu-bar state updates, then render compact text (`## ms` or `N/A`) and a color dot from derived state.

The right-click menu should be generated from app state (current host + switch flow, mode toggles, Settings, Quit) so it stays deterministic and testable. Left-click should toggle popover visibility. Ctrl-click and Cmd-click should route to the same context-menu path as right-click.

## Standard Stack

- `AppKit` (`NSStatusItem`, `NSStatusBarButton`, `NSMenu`, `NSPopover`) for menu bar + interactions.
- `SwiftUI` for popover content view.
- Existing Phase 1 services (`PingService`, `HostHealthTracker`, `PingScheduler`) for live ping data.
- `UserDefaults` for mode toggle persistence until full settings phase.

## Recommended Patterns

1. **Single source of truth for menu state**
   - Keep status color, display text, current host, and mode flags in one `@MainActor` view model.
   - Feed model updates from scheduler callback; UI only observes model.

2. **Latency smoothing for compact text**
   - Apply a lightweight exponential moving average (EMA) or bounded-step smoothing before rendering menu text.
   - Keep raw latency for future graph/history phases; smoothing only affects menu text display.

3. **Deterministic click routing**
   - Route `leftMouseUp` to popover toggle.
   - Route `rightMouseUp`, ctrl-click, and cmd-click to context menu.
   - If popover is visible and context menu opens, do not close popover.

4. **Context menu built from state, not hardcoded**
   - Build menu sections from current app state each time menu opens.
   - Host section: show current host and switch command path.
   - Mode section: compact + stay-on-top toggles in old-app visual style target.

## Pitfalls to Avoid

- Updating `NSStatusItem` off main thread.
- Hardcoding thresholds in multiple places (keep evaluator central).
- Treating single failed ping as immediate red (must honor sustained failure rule).
- Coupling context menu construction directly to AppKit callbacks (keep factory testable).
- Letting menu title grow with host names (phase decision is text-only latency).

## Implementation Notes For This Phase

- Honor locked decisions in `02-CONTEXT.md` for color semantics, compact text, click behavior, and menu grouping.
- Keep mode toggles functional as state and persistence now; full window behavior is completed in Phase 4.
- Use `N/A` when no measurable latency exists.

## Verification Guidance

- `swift build`
- `swift test`
- Manual run check:
  - Left-click toggles popover
  - Right-click/ctrl-click/cmd-click opens context menu
  - Menu text updates over time and remains compact
  - Status colors follow evaluator rules
