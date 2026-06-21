# Notifications Redesign Design

## Goal

Make the Notifications settings tab easier to understand by leading with alert noise level, then exposing specific alert categories and threshold tuning below it.

## Selected Direction

Use the preset-first layout from visual option C.

The page should answer the user’s first question: “How noisy should PingScope be?” It should not lead with a long list of individual alert switches. Presets provide a default policy, while individual controls remain available for users who want exact tuning.

## Layout

The Notifications tab keeps the existing settings window shell and sidebar.

The content area is organized into these sections:

1. Permission and master switch
   - Shows notification permission state.
   - Provides Send Test and Open Settings actions.
   - Keeps Enable Notifications as the top-level switch.

2. Alert Style
   - Segmented control with Quiet, Balanced, Verbose, and Custom.
   - Balanced is the recommended default.
   - Choosing Quiet, Balanced, or Verbose updates the alert types and thresholds to preset values.
   - Editing any individual alert type or threshold changes the style to Custom.

3. What Triggers Alerts
   - Compact grouped switches instead of a checkbox wall.
   - Availability: host down and recovery.
   - Network path: local network down, ISP path down, internet path down, remote service down.
   - Performance: high latency, internet loss, path degraded.
   - Network changes: network change alerts.

4. Network Status Colors
   - Keep the existing connected/no internet/no IP/not connected rows.
   - Display as a compact color list after trigger groups.

5. Advanced Thresholds
   - Collapsed disclosure by default.
   - Contains high latency ms, high latency consecutive pings, cooldown, internet loss failure ratio, path confidence, and path degraded consecutive diagnoses.
   - The existing controls remain, but the section is visually separated from common choices.

## Preset Behavior

Quiet:
- Host down, recovery, internet loss, local network down, ISP path down, internet path down, and remote service down enabled.
- High latency disabled.
- Path degraded disabled.
- Network change disabled.
- High latency after 10 pings when manually enabled.
- Path degraded after 5 diagnoses when manually enabled.

Balanced:
- Current default alert types remain enabled.
- Path degraded remains disabled by default.
- High latency after 5 pings.
- Internet loss at 100% failed.
- Path confidence balanced.
- Path degraded after 3 diagnoses.

Verbose:
- All alert types enabled, including path degraded.
- High latency after 3 pings.
- Internet loss at 75% failed.
- Path confidence sensitive.
- Path degraded after 2 diagnoses.

Custom:
- Appears automatically when the user changes any individual switch or threshold away from a preset.
- Does not overwrite the user’s choices.

## Visual Style

Keep the current PingScope dark settings style and sidebar. Use fewer icons in the main content area so icons communicate section identity rather than adding visual clutter. Rows should be compact, aligned, and readable at the current default settings window size.

## Testing

Add domain tests for notification preset application and custom detection.

Add UI-model-level tests if existing seams support it; otherwise keep the UI behavior simple and verify through the existing macOS smoke script after implementation.

Acceptance checks:
- The Notifications tab no longer appears as a long checkbox wall.
- Thresholds are still available but not the first thing users see.
- Changing a preset updates alert types and threshold values predictably.
- Editing a threshold or switch moves the style to Custom.
- Existing notification persistence remains backward compatible.
