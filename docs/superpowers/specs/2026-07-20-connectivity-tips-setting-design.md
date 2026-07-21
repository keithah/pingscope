# Connectivity Tips Setting Design

## Goal

Reduce repetitive router and degraded-network guidance by making the general connectivity diagnosis card optional and disabled by default.

## Behavior

- Add a persisted **Connectivity Tips** toggle to the iOS monitor settings, under **Display**.
- Default the toggle to off for new and existing installations that have never explicitly enabled it.
- When off, hide only the general connectivity diagnosis card that presents labels and explanations such as “Router” or “Degraded.”
- When on, show that card using the existing diagnosis presentation and content.
- Continue showing host health states, latency values, graph colors, notifications, widgets, and Live Activity state regardless of the toggle.
- Continue showing Starlink telemetry and alerts regardless of the toggle because they are operational measurements rather than general advice.

## Architecture

The app model owns and persists the setting in `UserDefaults`, following the existing display preference pattern. The model passes the current value and a mutation closure into `PingScopeIOSShell`. The shell exposes the toggle in settings and applies the value at the shipping monitor-insights rendering gate. Diagnosis computation remains unchanged so notification and other non-visual consumers retain their current behavior.

## Testing

Use behavioral RED tests against the shipping shell/app wiring where practical:

- A diagnosis is not rendered when the preference is absent or false.
- Enabling Connectivity Tips renders the diagnosis.
- Starlink telemetry remains eligible for rendering when Connectivity Tips is off.
- The preference defaults off and persists an explicit enabled value.

The implementation will follow RED, GREEN, and focused regression verification before broader project tests.

## Non-goals

- Do not change health classification, degraded thresholds, diagnosis generation, notifications, widget data, Live Activity state, network behavior, or Starlink telemetry.
- Do not modify `design/`.
