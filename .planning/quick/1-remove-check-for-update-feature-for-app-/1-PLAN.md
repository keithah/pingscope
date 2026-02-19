---
phase: quick-1
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - PingScope.xcodeproj/project.pbxproj
  - Sources/PingScope/Views/AboutView.swift
autonomous: true
requirements: []

must_haves:
  truths:
    - "App Store build does not show 'Check for Updates' button"
    - "Developer ID build continues to show 'Check for Updates' button"
    - "Both builds compile and run without errors"
  artifacts:
    - path: "PingScope.xcodeproj/project.pbxproj"
      provides: "APPSTORE build flag for App Store scheme"
      contains: "APPSTORE"
    - path: "Sources/PingScope/Views/AboutView.swift"
      provides: "Conditional check for updates button"
      contains: "#if !APPSTORE"
  key_links:
    - from: "PingScope.xcodeproj/project.pbxproj"
      to: "Sources/PingScope/Views/AboutView.swift"
      via: "APPSTORE compilation condition"
      pattern: "#if !APPSTORE"
---

<objective>
Remove "Check for Updates" feature from App Store build to comply with App Store Review Guidelines.

Purpose: App Store apps cannot include external update mechanisms - they must use Apple's built-in update system. The Developer ID build (distributed via GitHub) should retain the feature.
Output: Conditional compilation that hides the update button only in App Store builds.
</objective>

<execution_context>
@/Users/keith/.claude/get-shit-done/workflows/execute-plan.md
@/Users/keith/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@Sources/PingScope/Views/AboutView.swift
@PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme
@PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-DeveloperID.xcscheme
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add APPSTORE compilation condition to Xcode project</name>
  <files>PingScope.xcodeproj/project.pbxproj</files>
  <action>
Add APPSTORE compilation condition to the PingScopeApp target's Release build configuration:

1. Open PingScope.xcodeproj/project.pbxproj in text editor
2. Find the Release build configuration for PingScopeApp target (search for "buildSettings" and "Release")
3. Add to SWIFT_ACTIVE_COMPILATION_CONDITIONS: "APPSTORE" for App Store build
4. Ensure Developer ID build does NOT have APPSTORE flag

Implementation approach:
- Locate the xcBuildConfiguration sections for PingScopeApp target
- Find the Release configuration (used by both schemes during Archive)
- Since both schemes use the same target, we need to use xcconfig files or scheme-specific settings
- Alternative: Use preprocessor macros based on code signing identity or provisioning profile
- Simplest: Add "APPSTORE" to OTHER_SWIFT_FLAGS = "-D APPSTORE" in App Store scheme's build settings

Actually, since schemes cannot directly set compilation conditions, we need to:
- Check if there are separate build configurations (like "Release-AppStore" vs "Release-DeveloperID")
- If not, create them OR use the signing identity to conditionally define the flag
- Most practical: Manually set in Xcode build settings for each scheme, which stores in xcscheme files

For this quick task, manually edit the xcscheme files to add build settings:
- Add to PingScope-AppStore.xcscheme: buildSettings with SWIFT_ACTIVE_COMPILATION_CONDITIONS including APPSTORE
- Keep PingScope-DeveloperID.xcscheme without this flag
  </action>
  <verify>
Run: grep -r "APPSTORE" PingScope.xcodeproj/
Should show APPSTORE flag configured for App Store scheme
  </verify>
  <done>
APPSTORE compilation condition configured in Xcode project settings for App Store builds only
  </done>
</task>

<task type="auto">
  <name>Task 2: Conditionally hide Check for Updates button in AboutView</name>
  <files>Sources/PingScope/Views/AboutView.swift</files>
  <action>
Wrap the "Check for Updates" button (lines 71-76) with conditional compilation:

Replace:
```swift
            Button {
                NSWorkspace.shared.open(Self.releasesURL)
            } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.link)
```

With:
```swift
            #if !APPSTORE
            Button {
                NSWorkspace.shared.open(Self.releasesURL)
            } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.link)
            #endif
```

This hides the button when APPSTORE is defined (App Store build), shows it otherwise (Developer ID build).
  </action>
  <verify>
1. Build App Store scheme: xcodebuild -scheme PingScope-AppStore -configuration Release clean build
2. Build Developer ID scheme: xcodebuild -scheme PingScope-DeveloperID -configuration Release clean build
3. Both should compile without errors
4. Visually inspect: Run App Store build, open About window (should NOT show Check for Updates)
5. Visually inspect: Run Developer ID build, open About window (should show Check for Updates)
  </verify>
  <done>
AboutView conditionally hides "Check for Updates" button in App Store builds only, shows in Developer ID builds
  </done>
</task>

<task type="auto">
  <name>Task 3: Test both build configurations</name>
  <files></files>
  <action>
Build and verify both configurations work correctly:

1. Build App Store scheme:
   xcodebuild -scheme PingScope-AppStore -configuration Release -derivedDataPath .build/appstore clean build

2. Build Developer ID scheme:
   xcodebuild -scheme PingScope-DeveloperID -configuration Release -derivedDataPath .build/developerid clean build

3. Verify both builds:
   - Check build logs for successful compilation
   - Check that no warnings about undefined APPSTORE flag
   - Confirm both .app bundles created

4. Optional manual verification (describe steps):
   - Launch App Store build from .build/appstore/.../PingScope.app
   - Open About window (Help menu or CMD+comma)
   - Confirm "Check for Updates" button is NOT visible
   - Launch Developer ID build from .build/developerid/.../PingScope.app
   - Open About window
   - Confirm "Check for Updates" button IS visible and works (opens releases page)
  </action>
  <verify>
Both build schemes compile successfully without errors:
- xcodebuild exit code 0 for both schemes
- No compiler warnings about APPSTORE flag
- Both .app bundles exist in respective derivedDataPath locations
  </verify>
  <done>
Both App Store and Developer ID builds compile cleanly with correct conditional compilation behavior
  </done>
</task>

</tasks>

<verification>
1. Run: xcodebuild -scheme PingScope-AppStore -configuration Release -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS
   Should show APPSTORE flag included
2. Run: xcodebuild -scheme PingScope-DeveloperID -configuration Release -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS
   Should NOT show APPSTORE flag
3. Build both schemes successfully
4. AboutView.swift contains #if !APPSTORE wrapper around Check for Updates button
</verification>

<success_criteria>
- APPSTORE compilation condition configured in Xcode project
- AboutView.swift conditionally compiles Check for Updates button
- App Store build does not show the button
- Developer ID build shows the button
- Both builds compile without errors
- Both builds run without crashes
- Ready for App Store submission without update mechanism
</success_criteria>

<output>
After completion, create `.planning/quick/1-remove-check-for-update-feature-for-app-/1-SUMMARY.md`
</output>
