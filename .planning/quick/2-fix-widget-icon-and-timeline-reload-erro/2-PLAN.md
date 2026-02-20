---
phase: quick-2
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - PingScopeWidget/Info.plist
  - Sources/PingScope/Widget/WidgetDataStore.swift
autonomous: true

must_haves:
  truths:
    - "Widget extension has required 512x512@2x icon in ICNS format for App Store submission"
    - "Timeline reload calls do not generate ChronoCoreErrorDomain Code=27 errors"
    - "Widget can be added to macOS desktop/Notification Center without errors"
  artifacts:
    - path: "PingScopeWidget/Info.plist"
      provides: "CFBundleIconFile pointing to AppIcon for widget extension"
      contains: "CFBundleIconFile"
    - path: "Sources/PingScope/Widget/WidgetDataStore.swift"
      provides: "Timeline reload with error handling"
      min_lines: 30
  key_links:
    - from: "PingScopeWidget/Info.plist"
      to: "Assets.xcassets/AppIcon.appiconset"
      via: "CFBundleIconFile reference"
      pattern: "CFBundleIconFile.*AppIcon"
    - from: "Sources/PingScope/Widget/WidgetDataStore.swift"
      to: "WidgetCenter.shared"
      via: "reloadTimelines call"
      pattern: "WidgetCenter\\.shared\\.reloadTimelines"
---

<objective>
Fix widget extension App Store compliance and runtime errors

Purpose: Resolve two critical widget extension errors preventing App Store submission and causing runtime failures:
1. Missing required ICNS icon (512x512@2x) in widget bundle
2. Timeline reload failures (ChronoCoreErrorDomain Code=27)

Output: Widget extension ready for App Store with proper icon and stable timeline updates
</objective>

<execution_context>
@/Users/keith/.claude/get-shit-done/workflows/execute-plan.md
@/Users/keith/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.planning/ROADMAP.md

## Current Widget Setup

From Phase 17 (Widget Foundation):
- Plan 17-01: Created widget extension target with App Groups (complete)
- Plan 17-02: Created widget UI with TimelineProvider (complete)
- Plan 17-03: Integration with main app (NOT YET STARTED)

## Error Context

**Error 1: Missing ICNS icon**
```
The application bundle does not have an icon in ICNS format
containing a 512pt x 512pt @2x image
```

**Error 2: Timeline reload failures**
```
reloadTimelines(ofKind:) - error reloading timelines of kind
'PingScopeWidget': Error Domain=ChronoCoreErrorDomain Code=27
```

## Current State

- Main app has Assets.xcassets/AppIcon.appiconset with all required sizes (including 512x512@2x)
- Main app Info.plist has `CFBundleIconFile = AppIcon` (working)
- Widget Info.plist MISSING `CFBundleIconFile` key
- WidgetDataStore calls `reloadTimelines(ofKind: "PingScopeWidget")` but widget may not be properly registered yet

## Related Files

@Assets.xcassets/AppIcon.appiconset/Contents.json
@PingScopeWidget/Info.plist
@PingScopeWidget/PingScopeWidget.swift
@Sources/PingScope/Widget/WidgetDataStore.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add CFBundleIconFile to Widget Info.plist</name>
  <files>PingScopeWidget/Info.plist</files>
  <action>
Add `CFBundleIconFile` key to widget Info.plist pointing to AppIcon asset catalog:

1. Open PingScopeWidget/Info.plist
2. Add after `CFBundleExecutable` key:
```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

This allows the widget extension to inherit the same AppIcon.appiconset from Assets.xcassets that the main app uses. The asset catalog already contains all required sizes including 512x512@2x (201KB icon_512x512@2x.png).

**Why this works**: Widget extensions share the main app's asset catalog in Xcode's build process. The CFBundleIconFile key tells the system to look for the AppIcon asset, which will be compiled into the widget bundle during build.
  </action>
  <verify>
1. Verify key added: `grep CFBundleIconFile PingScopeWidget/Info.plist`
2. Verify value is AppIcon: `grep -A1 CFBundleIconFile PingScopeWidget/Info.plist | grep AppIcon`
3. Build widget target: `xcodebuild -scheme PingScopeWidget -configuration Release clean build`
  </verify>
  <done>
- PingScopeWidget/Info.plist contains CFBundleIconFile key with value "AppIcon"
- Widget extension builds without icon-related errors
- Archive validation will pass icon requirements
  </done>
</task>

<task type="auto">
  <name>Task 2: Add Error Handling to Timeline Reload</name>
  <files>Sources/PingScope/Widget/WidgetDataStore.swift</files>
  <action>
Update WidgetDataStore to handle timeline reload errors gracefully:

1. Import os.log for logging
2. Wrap `reloadTimelines(ofKind:)` call in error handling
3. Add fallback to `reloadAllTimelines()` if specific kind fails

Replace the current single-line reload:
```swift
WidgetCenter.shared.reloadTimelines(ofKind: "PingScopeWidget")
```

With error-handled version:
```swift
#if canImport(WidgetKit)
import os.log

// In updateWidgetData method, after encoding:
do {
    // Try reloading specific widget kind first
    WidgetCenter.shared.reloadTimelines(ofKind: "PingScopeWidget")
} catch {
    // Fallback to reloading all timelines if specific kind fails
    // This handles cases where widget isn't registered yet (ChronoCoreErrorDomain Code=27)
    os_log(.debug, "Failed to reload PingScopeWidget timelines (Code=27), reloading all: %{public}@", error.localizedDescription)
    WidgetCenter.shared.reloadAllTimelines()
}
#endif
```

**Why Code=27 happens**: ChronoCoreErrorDomain Code=27 occurs when calling `reloadTimelines(ofKind:)` for a widget that hasn't been added to the system yet. The widget exists in the bundle but isn't instantiated. `reloadAllTimelines()` is safer during development and doesn't fail when no widgets are active.

**Future improvement**: Plan 17-03 (Integration) will wire WidgetDataStore into the main app's ping monitoring loop, ensuring data is actually written before reload calls.
  </action>
  <verify>
1. Verify import added: `grep "import os" Sources/PingScope/Widget/WidgetDataStore.swift`
2. Verify error handling: `grep -A3 "catch" Sources/PingScope/Widget/WidgetDataStore.swift`
3. Verify fallback: `grep "reloadAllTimelines" Sources/PingScope/Widget/WidgetDataStore.swift`
4. Build project: `swift build`
  </verify>
  <done>
- WidgetDataStore has error handling around reloadTimelines call
- Code=27 errors are caught and handled with reloadAllTimelines fallback
- Debug logging explains why fallback was used
- Build succeeds without WidgetKit errors
  </done>
</task>

</tasks>

<verification>
**Icon verification:**
1. `grep CFBundleIconFile PingScopeWidget/Info.plist` shows AppIcon value
2. Archive the app and validate - no icon errors

**Timeline reload verification:**
1. Build succeeds without WidgetKit errors
2. Console logs show no ChronoCoreErrorDomain Code=27 errors (or they're caught and handled)
3. WidgetDataStore can write data without crashing

**Integration readiness:**
- Widget Info.plist complete and App Store compliant
- Timeline reload robust and won't crash if widget not added yet
- Ready for Plan 17-03 (Integration) where WidgetDataStore gets wired to actual ping monitoring
</verification>

<success_criteria>
**Measurable completion:**

1. **Icon compliance**: Widget Info.plist contains `CFBundleIconFile = AppIcon`, build succeeds, archive validation passes
2. **Timeline stability**: No unhandled Code=27 errors, reloadAllTimelines fallback implemented
3. **Build health**: `xcodebuild -scheme PingScopeWidget` succeeds with 0 errors
4. **App Store readiness**: Widget bundle has required 512x512@2x icon in manifest

**User-facing outcome:**
- Widget extension ready for App Store submission (icon requirement met)
- No crash/error logs from timeline reload attempts
- Foundation stable for Plan 17-03 integration work
</success_criteria>

<output>
After completion, create `.planning/quick/2-fix-widget-icon-and-timeline-reload-erro/2-SUMMARY.md`
</output>
