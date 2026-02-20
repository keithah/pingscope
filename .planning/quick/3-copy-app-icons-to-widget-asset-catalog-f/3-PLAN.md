---
phase: 3-copy-app-icons-to-widget-asset-catalog-f
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - widget/Assets.xcassets/AppIcon.appiconset/icon_16x16.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_32x32.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_128x128.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_256x256.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_512x512.png
  - widget/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
autonomous: true
requirements: []

must_haves:
  truths:
    - "Widget extension bundle contains 512x512@2x icon in ICNS format"
    - "App Store validation passes icon requirements"
    - "Widget displays app icon in system widget picker"
  artifacts:
    - path: "widget/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
      provides: "Required 512x512@2x icon for App Store compliance"
      min_size: 200000
    - path: "widget/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
      provides: "512x512 icon"
      min_size: 128000
    - path: "widget/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
      provides: "256x256@2x icon"
      min_size: 128000
  key_links:
    - from: "widget/Info.plist"
      to: "widget/Assets.xcassets/AppIcon.appiconset"
      via: "CFBundleIconFile reference"
      pattern: "CFBundleIconFile.*AppIcon"
---

<objective>
Copy all 10 icon PNG files from main app's asset catalog to widget extension's asset catalog to satisfy App Store ICNS format requirements.

Purpose: Fix App Store validation error "Missing required icon. The application bundle does not have an icon in ICNS format containing a 512pt x 512pt @2x image" by providing complete icon set in widget's own asset catalog.

Output: Widget extension with complete AppIcon.appiconset containing all required icon sizes (16x16 through 512x512@2x).
</objective>

<execution_context>
@/Users/keith/.claude/get-shit-done/workflows/execute-plan.md
@/Users/keith/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md

**Issue Context:**
- App Store validation error: Widget bundle missing 512x512@2x icon in ICNS format
- Widget's Info.plist correctly sets CFBundleIconFile to "AppIcon"
- Widget's asset catalog exists at widget/Assets.xcassets/AppIcon.appiconset
- BUT: Widget's AppIcon.appiconset has only Contents.json, no actual PNG files
- Main app's asset catalog has complete set of 10 icon files (16x16 through 512x512@2x)

**Previous Related Work:**
- Quick task 2: Set CFBundleIconFile to "AppIcon" in widget Info.plist (complete)
- This task completes the icon setup by providing the actual image files
</context>

<tasks>

<task type="auto">
  <name>Copy icon PNG files from main app to widget asset catalog</name>
  <files>
    widget/Assets.xcassets/AppIcon.appiconset/icon_16x16.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_32x32.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_128x128.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_256x256.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_512x512.png
    widget/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
  </files>
  <action>
Copy all 10 icon PNG files from Assets.xcassets/AppIcon.appiconset/ to widget/Assets.xcassets/AppIcon.appiconset/ directory.

Files to copy:
- icon_16x16.png (876 bytes)
- icon_16x16@2x.png (5,338 bytes)
- icon_32x32.png (2,101 bytes)
- icon_32x32@2x.png (8,157 bytes)
- icon_128x128.png (14,836 bytes)
- icon_128x128@2x.png (52,817 bytes)
- icon_256x256.png (52,817 bytes)
- icon_256x256@2x.png (128,025 bytes)
- icon_512x512.png (128,025 bytes)
- icon_512x512@2x.png (201,247 bytes) ← CRITICAL for App Store

Use cp command to preserve file metadata. The widget's Contents.json already exists and references these filenames, so no JSON changes needed.
  </action>
  <verify>
Verify all 10 PNG files exist in widget asset catalog:
```bash
ls -lh widget/Assets.xcassets/AppIcon.appiconset/*.png | wc -l  # Should be 10
ls -lh widget/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png  # Should show ~201KB
```
  </verify>
  <done>
All 10 icon PNG files exist in widget/Assets.xcassets/AppIcon.appiconset/ with correct file sizes matching source files. Widget extension now has complete icon set for ICNS compilation.
  </done>
</task>

<task type="auto">
  <name>Build and verify widget bundle contains icons</name>
  <files>N/A</files>
  <action>
Build the PingScope project for App Store configuration to verify Xcode compiles the widget's AppIcon.appiconset into proper ICNS format in the widget bundle.

Clean build folder first to ensure fresh compilation:
```bash
xcodebuild clean -project PingScope.xcodeproj -scheme PingScope-AppStore
```

Then build App Store scheme:
```bash
xcodebuild build -project PingScope.xcodeproj -scheme PingScope-AppStore -configuration Release
```

After successful build, inspect the widget bundle to confirm icon assets are present. The ICNS file should be generated automatically by Xcode from the AppIcon.appiconset.
  </action>
  <verify>
Check build output for successful compilation without icon warnings:
```bash
# Build should complete without "Missing required icon" errors
# Check widget bundle structure (path will be in DerivedData)
```

Search build log for icon-related warnings or errors. Build should succeed with no ICNS-related issues.
  </verify>
  <done>
PingScope-AppStore scheme builds successfully for Release configuration. Build log shows no icon-related errors or warnings. Widget extension bundle is ready for App Store submission with complete icon set.
  </done>
</task>

</tasks>

<verification>
**Automated verification:**
1. All 10 PNG files present in widget/Assets.xcassets/AppIcon.appiconset/
2. File sizes match source files from main app asset catalog
3. icon_512x512@2x.png is ~201KB (the critical file for App Store validation)
4. Clean build of PingScope-AppStore scheme completes without icon warnings

**Manual verification (if needed):**
1. Archive build for App Store submission
2. Run "Validate App" in Xcode Organizer
3. Confirm no "Missing required icon" errors in validation results
</verification>

<success_criteria>
Widget extension asset catalog contains complete icon set (10 PNG files, 16x16 through 512x512@2x). App Store build compiles without icon-related errors. Widget bundle ready for resubmission to App Store with ICNS format compliance.
</success_criteria>

<output>
After completion, create `.planning/quick/3-copy-app-icons-to-widget-asset-catalog-f/3-SUMMARY.md` with:
- List of copied icon files with sizes
- Build verification results
- Next step: Archive and resubmit to App Store
</output>
