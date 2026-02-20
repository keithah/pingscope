---
phase: quick-4
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - PingScope.xcodeproj/project.pbxproj
autonomous: true
requirements: [QUICK-4]

must_haves:
  truths:
    - "Widget target has ASSETCATALOG_COMPILER_APPICON_NAME build setting in both Debug and Release configurations"
    - "Xcode compiles widget's AppIcon.appiconset into ICNS format during build"
    - "App Store validation passes icon requirements for widget extension"
  artifacts:
    - path: "PingScope.xcodeproj/project.pbxproj"
      provides: "ASSETCATALOG_COMPILER_APPICON_NAME setting for widgetExtension target"
      contains: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"
      min_lines: 700
  key_links:
    - from: "PingScope.xcodeproj/project.pbxproj"
      to: "widget/Assets.xcassets/AppIcon.appiconset"
      via: "ASSETCATALOG_COMPILER_APPICON_NAME build setting"
      pattern: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"
---

<objective>
Add ASSETCATALOG_COMPILER_APPICON_NAME build setting to widget target to fix App Store validation.

Purpose: Without this build setting, Xcode doesn't compile the widget's AppIcon.appiconset into ICNS format, causing App Store validation to reject the widget extension for missing icons.

Output: Updated project.pbxproj with proper asset catalog configuration for widget target.
</objective>

<execution_context>
@/Users/keith/.claude/get-shit-done/workflows/execute-plan.md
@/Users/keith/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md

Previous quick tasks:
- quick-2: Configured widget Info.plist with CFBundleIconFile key
- quick-3: Copied complete icon set to widget/Assets.xcassets/AppIcon.appiconset/
</context>

<tasks>

<task type="auto">
  <name>Add ASSETCATALOG_COMPILER_APPICON_NAME to widget target configurations</name>
  <files>PingScope.xcodeproj/project.pbxproj</files>
  <action>
Add ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; to both Debug and Release configurations of the widgetExtension target.

**Target locations:**
- Debug config (line ~673): Add after ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME
- Release config (line ~707): Add after ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME

**Pattern to follow from main app target (lines 509-510):**
```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
```

**Implementation:**
1. Read project.pbxproj
2. Locate widgetExtension Debug config (starts at line 670)
3. Add line after ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME:
   `				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`
4. Locate widgetExtension Release config (starts at line 703)
5. Add same line after ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME
6. Maintain identical indentation (tabs) as surrounding lines
  </action>
  <verify>
```bash
# Verify both Debug and Release configs have the setting
grep -A2 "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME" PingScope.xcodeproj/project.pbxproj | grep "ASSETCATALOG_COMPILER_APPICON_NAME"
```

Expected: Two matches (one for Debug, one for Release)
  </verify>
  <done>
- ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; appears in Debug config after line 674
- ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; appears in Release config after line 708
- Both instances use correct indentation matching other ASSETCATALOG_COMPILER_* settings
  </done>
</task>

<task type="auto">
  <name>Verify Xcode can locate widget app icon asset catalog</name>
  <files></files>
  <action>
Validate that the widget's AppIcon.appiconset exists and contains all required files.

**Check:**
1. widget/Assets.xcassets/AppIcon.appiconset/Contents.json exists
2. All 10 PNG files referenced in Contents.json exist
3. Contents.json has valid JSON structure

This ensures the build setting points to a valid asset catalog entry.
  </action>
  <verify>
```bash
# Verify asset catalog structure
test -f widget/Assets.xcassets/AppIcon.appiconset/Contents.json && \
test -f widget/Assets.xcassets/AppIcon.appiconset/icon_16x16.png && \
test -f widget/Assets.xcassets/AppIcon.appiconset/icon_32x32.png && \
echo "Widget AppIcon asset catalog valid"
```
  </verify>
  <done>
- widget/Assets.xcassets/AppIcon.appiconset/Contents.json exists
- All 10 PNG icon files exist in the appiconset directory
- Contents.json is valid JSON with proper filename references
  </done>
</task>

</tasks>

<verification>
1. project.pbxproj contains ASSETCATALOG_COMPILER_APPICON_NAME in both widget target configurations
2. Widget's AppIcon.appiconset structure is complete and valid
3. Build setting matches pattern used in main app target
</verification>

<success_criteria>
- ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; added to widgetExtension Debug config
- ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; added to widgetExtension Release config
- Widget asset catalog structure validated as complete
- Ready for archive build and App Store submission
</success_criteria>

<output>
After completion, create `.planning/quick/4-add-assetcatalog-compiler-appicon-name-b/4-01-SUMMARY.md`
</output>
