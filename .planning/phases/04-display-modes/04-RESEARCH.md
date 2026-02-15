# Phase 4: Display Modes - Research

**Researched:** 2026-02-14
**Domain:** macOS menu bar window presentation (popover/full/compact/floating), per-mode state persistence, AppKit window behavior
**Confidence:** HIGH

## Summary

Phase 4 is primarily a window-presentation and UI-state phase, not a networking phase. The existing Phase 2/3 architecture already has the right seam: `AppDelegate` coordinates presentation, `MenuBarRuntime` owns mode preferences, and `StatusItemController` provides anchor context via the status item button. The critical planning move is to introduce a dedicated display state model (per mode) and keep runtime host-monitoring flow unchanged.

Locked decisions from `04-CONTEXT.md` are implementable with current stack (SwiftUI + AppKit, no new dependencies): full mode (`450x500`) with host pills + graph + recent results, compact mode (`280x220`) with host dropdown + graph + recent results, mode switch from both settings and quick toggle, and borderless stay-on-top floating behavior with a drag handle.

All `images/*` references were reviewed. Visual direction is consistent: dark panel shell, segmented/pill host selector in full mode, dropdown selector in compact mode, graph-first stack, recent-results list immediately below graph, and small utility controls in top-right. Planning should treat these as composition constraints, with icon/timing/spacing as discretionary polish.

**Primary recommendation:** Implement a `DisplayModeCoordinator` + `DisplayPreferencesStore` that separates presentation mechanics (popover vs floating window) from mode UI state (full vs compact), persisting frame/collapse settings per mode and preserving shared state (selected host + time range) across mode switches.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version / Availability | Purpose | Why Standard |
|---------|------------------------|---------|--------------|
| SwiftUI | macOS 13+ | Full/compact content views and mode-specific layouts | Already used throughout UI layer |
| AppKit (`NSPopover`, `NSWindow`) | macOS 13+ target, AppKit APIs stable since much earlier | Menu-bar anchoring, borderless floating window, window level/collection behavior | Required for status-item anchored utility apps |
| Foundation (`UserDefaults`) | Built-in | Persist mode toggles, frame sizes, panel visibility | Already used in `ModePreferenceStore` and `HostStore` |

### Supporting
| Library | Version / Availability | Purpose | When to Use |
|---------|------------------------|---------|-------------|
| Combine (`@Published`) | Built-in | Keep context menu/popover/window UI in sync with mode state | Existing pattern in `MenuBarViewModel` and `StatusPopoverViewModel` |
| AppKit window frame autosave APIs | `setFrameAutosaveName`, `saveFrameUsingName` | Persist and restore user-resized window frames per mode | Better than hand-rolled geometry serialization |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| AppKit-driven floating window control | SwiftUI scene modifiers (`windowLevel`, `windowBackgroundDragBehavior`) | SwiftUI-only APIs are macOS 15+; deployment target is macOS 13 |
| Shared single frame key | Separate per-mode frame keys | Per-mode keys match locked requirement (remember full/compact independently) |

**Installation:**
```bash
# No new packages required
```

## Architecture Patterns

### Recommended Project Structure
```
Sources/PingMonitor/
├── MenuBar/
│   ├── DisplayModeCoordinator.swift      # NEW: popover/window routing + anchor positioning
│   ├── DisplayPreferencesStore.swift     # NEW: per-mode UI/frame persistence
│   └── ModePreferenceStore.swift         # existing compact/stay-on-top toggles
├── ViewModels/
│   └── DisplayViewModel.swift            # NEW: selected host/time range + per-mode panel visibility
├── Views/
│   ├── FullModeView.swift                # NEW: host pills + graph + recent results
│   ├── CompactModeView.swift             # NEW: dropdown + condensed graph/results
│   └── WindowDragHandleView.swift        # NEW: explicit drag handle region
└── App/
    └── AppDelegate.swift                 # updated orchestration only
```

### Pattern 1: Presentation Shell Coordinator
**What:** One coordinator decides whether to show an `NSPopover` or borderless `NSWindow` based on `isStayOnTopEnabled`, while content selection (full/compact) is driven by `isCompactModeEnabled`.
**When to use:** Every status-item click and mode toggle.
**Example:**
```swift
@MainActor
final class DisplayModeCoordinator {
    func open(from button: NSStatusBarButton, state: DisplayState) {
        if state.isStayOnTopEnabled {
            showFloatingWindow(anchoredTo: button, mode: state.mode)
        } else {
            showPopover(anchoredTo: button, mode: state.mode)
        }
    }
}
```

### Pattern 2: Split Shared vs Per-Mode UI State
**What:** Persist shared state once (`selectedHostID`, `selectedTimeRange`), but persist panel visibility and frame separately for `.full` and `.compact`.
**When to use:** On mode switch, app launch, and close/reopen cycles.
**Example:**
```swift
struct DisplaySharedState: Codable {
    var selectedHostID: UUID?
    var selectedTimeRange: TimeRange = .fiveMinutes
}

struct ModeState: Codable {
    var graphVisible: Bool = true
    var historyVisible: Bool = true
    var frame: CGRect?
}
```

### Pattern 3: Anchor + Clamp Positioning Near Status Item
**What:** Convert status-item button frame to screen coordinates, then place window below/near icon and clamp to visible screen frame.
**When to use:** After mode switch and every reopen for floating window.
**Example:**
```swift
func anchorRect(for button: NSStatusBarButton) -> NSRect? {
    guard let buttonWindow = button.window else { return nil }
    return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
}
```

### Pattern 4: Drag Handle Only (Not Background Drag)
**What:** Keep `window.isMovableByWindowBackground = false`; start drag only from dedicated handle region by forwarding mouse-down to `window.performDrag(with:)`.
**When to use:** Borderless floating window implementation.
**Example:**
```swift
final class DragHandleNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
```

### Anti-Patterns to Avoid
- **Single mutable window state blob:** makes per-mode memory and shared-state preservation easy to break.
- **Using `.canJoinAllSpaces` for floating window:** violates locked requirement (current Space only).
- **`isMovableByWindowBackground = true`:** violates drag-handle-only requirement.
- **Rebuilding host selection state in each view:** risks losing selected host on mode switch.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window frame persistence | Manual JSON encode/decode of sizes and positions | `setFrameAutosaveName` / `saveFrameUsingName` (+ fallback keys) | Native behavior handles restore timing and edge cases |
| Popover anchoring math | Custom global coordinate transforms only | `NSPopover.show(relativeTo:of:preferredEdge:)` | AppKit handles edge flipping and tracking anchor movement |
| Dragging borderless window | Global drag-anywhere hit-testing | Dedicated handle + `NSWindow.performDrag(with:)` | Matches requirement and preserves control interactivity |
| Space behavior | Custom Space detection logic | `NSWindow.collectionBehavior` flags (avoid all-spaces flags) | Correct integration with Mission Control/Spaces |

**Key insight:** AppKit already provides the exact primitives for this phase; planning should wire them together, not replace them.

## Common Pitfalls

### Pitfall 1: Floating Window Appears in Every Space
**What goes wrong:** Window follows user across Spaces.
**Why it happens:** `.canJoinAllSpaces` (or equivalent all-spaces behavior) is set.
**How to avoid:** Keep collection behavior off all-spaces flags; use mode reopen anchoring logic instead.
**Warning signs:** Switching Spaces keeps showing PingMonitor floating window.

### Pitfall 2: Mode Switch Loses Selection Context
**What goes wrong:** Selected host and/or time range reset when switching full/compact.
**Why it happens:** State is stored in mode-local view structs instead of shared model.
**How to avoid:** Centralize shared state in one view model/store, with per-mode overlays only for panel/frame state.
**Warning signs:** Toggling compact mode jumps back to default host.

### Pitfall 3: Drag Handle Requirement Accidentally Broken
**What goes wrong:** Entire window background drags.
**Why it happens:** `isMovableByWindowBackground = true` left enabled.
**How to avoid:** Disable background drag and wire explicit handle region.
**Warning signs:** Clicking graph/history area drags window.

### Pitfall 4: Off-Screen Reopen After Resize/Display Changes
**What goes wrong:** Floating window opens partially or fully off-screen.
**Why it happens:** Restored frame not clamped to current `visibleFrame`.
**How to avoid:** Clamp restored origin/size per current screen before showing.
**Warning signs:** App appears "not opening" until Mission Control reveals it off-screen.

### Pitfall 5: Phase Boundary Drift into Visualization Scope
**What goes wrong:** Phase 4 expands into full VIS-01..VIS-07 implementation.
**Why it happens:** Graph/history UI scaffolding invites feature creep.
**How to avoid:** Build mode shells + data plumbing only needed for display-mode behavior; keep advanced chart/statistics semantics for Phase 5.
**Warning signs:** Planning tasks include stats math, export logic, or full graph interaction controls.

## Code Examples

Verified patterns from SDK headers and current project:

### Borderless Floating Window + Current Space Behavior
```swift
let window = NSWindow(
    contentRect: .init(origin: .zero, size: initialSize),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.isMovableByWindowBackground = false
window.collectionBehavior = [.transient, .moveToActiveSpace]
```

### Popover Anchored to Status Item
```swift
guard let button = statusItemController.button else { return }
popover.behavior = .applicationDefined
popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
```

### Persist Mode Toggles (Already in Project)
```swift
final class ModePreferenceStore {
    var isCompactModeEnabled: Bool {
        get { userDefaults.bool(forKey: compactModeKey) }
        set { userDefaults.set(newValue, forKey: compactModeKey) }
    }
}
```

### Shared + Per-Mode State Save Contract
```swift
enum DisplayMode: String, Codable { case full, compact }

struct DisplayPreferences: Codable {
    var shared: DisplaySharedState
    var full: ModeState
    var compact: ModeState
    var reopenFloatingAfterClose: Bool
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AppKit-only drag behavior flags (`isMovableByWindowBackground`) | New SwiftUI `WindowDragGesture` + `windowBackgroundDragBehavior` APIs | macOS 15 | Not usable for this project target (macOS 13), so use AppKit path |
| One-size popover content | Mode-specific full/compact composition with shared state | This phase | Enables DISP-01..DISP-03 without regressing host-selection continuity |
| Stateless reopen | Persisted mode/frame and anchor-aware reopen | This phase | Enables predictable user experience and DISP-06 compliance |

**Deprecated/outdated for this project target:**
- SwiftUI scene-level window interaction APIs as primary mechanism (macOS 15+ only).

## Open Questions

1. **How much real graph/history behavior should be implemented in Phase 4 vs scaffolded for Phase 5?**
   - What we know: Phase 4 requires display modes and composition; Phase 5 owns visualization requirements.
   - What's unclear: Minimum behavior needed to avoid UI placeholders feeling incomplete.
   - Recommendation: Plan Phase 4 to render real recent ping rows and basic trend line from existing scheduler outputs, but defer statistics/math/filter richness to Phase 5.

2. **Where to host mode toggles in "settings" before full settings phase?**
   - What we know: Locked decision requires toggles in settings and quick toggle.
   - What's unclear: Final settings UI belongs to Phase 6.
   - Recommendation: Add a lightweight interim settings sheet section for display toggles now, reusing persisted keys so Phase 6 can adopt without migration.

## Sources

### Primary (HIGH confidence)
- Project source:
  - `Sources/PingMonitor/App/AppDelegate.swift`
  - `Sources/PingMonitor/MenuBar/ModePreferenceStore.swift`
  - `Sources/PingMonitor/MenuBar/StatusItemController.swift`
  - `Sources/PingMonitor/MenuBar/MenuBarRuntime.swift`
- Visual baselines (all reviewed):
  - `images/mainscreen.png`, `images/mainscreen_proper.png`, `images/mainscreen_final.png`, `images/mainscreen_appstore.png`
  - `images/compact.png`, `images/compact_proper.png`, `images/compact_final.png`, `images/compact_appstore.png`
  - `images/settings.png`, `images/settings_proper.png`, `images/settings_final.png`, `images/settings_appstore.png` (style-only context)
- Apple SDK headers (authoritative local documentation):
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSWindow.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSPopover.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSPanel.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`

### Secondary (MEDIUM confidence)
- None required for core claims.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Current project and Apple SDK headers align directly with phase needs.
- Architecture: HIGH - Fits existing AppDelegate/runtime seams and locked decisions.
- Pitfalls: HIGH - Derived from explicit AppKit semantics and current code behavior.

**Research date:** 2026-02-14
**Valid until:** 2026-03-16 (30 days; APIs stable, but re-check if deployment target changes)
