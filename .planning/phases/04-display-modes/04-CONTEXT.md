# Phase 4: Display Modes - Context

**Gathered:** 2026-02-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement two display modes for PingMonitor and mode switching behavior: full view (450x500), compact view (280x220), toggling between modes, and optional stay-on-top floating window behavior.

</domain>

<decisions>
## Implementation Decisions

### Visual reference baseline
- Use the designs in `images/` as the visual baseline for Phase 4 behavior and layout direction.
- Full mode should follow the `mainscreen*` composition language.
- Compact mode should follow the `compact*` composition language.

### Full view content and layout
- Default full view content is **Hosts + Graph + Recent Results**.
- Host switching in full view uses **top host pills** (Google/Cloudflare/Gateway style), not dropdown.
- Graph and history panels are **independently collapsible** in full view.
- Full view allows manual resize and should **persist user-adjusted full size**.

### Compact view content and layout
- Compact mode keeps a **top dropdown host selector**.
- Compact default content is **Graph + Recent Results**.
- Compact recent results should show **6 rows before scrolling**.
- Compact starts from target dimensions but should **remember last compact size**.

### Mode switch behavior
- Mode switching is available in **both** places: settings toggle and quick toggle.
- Switching modes preserves **selected host and time range**.
- Panel visibility memory is **per mode** (full and compact remember separately).
- After mode switch, reopen/position behavior should anchor **near menu bar icon**.

### Floating window behavior
- Stay-on-top window is **borderless with a drag handle** (not drag-anywhere).
- Floating mode is available in **both full and compact** views.
- If user closes floating window, next open should **reopen in floating mode**.
- Floating window should stay in **current Space only** (not all Spaces).

### Claude's Discretion
- Exact iconography polish for mode toggles and compact controls.
- Exact animation timing for mode switches and panel collapse/expand.
- Fine spacing/typography tweaks as long as they preserve the selected mock direction.

</decisions>

<specifics>
## Specific Ideas

- User explicitly requested all images in `images/` be reviewed and used as the look-and-feel baseline.
- Full view reference: segmented host controls, graph-first layout, recent-results table beneath.
- Compact reference: dense, information-forward panel with dropdown host selector and condensed graph/history stack.

</specifics>

<deferred>
## Deferred Ideas

- Settings panel visual/system details shown in `settings*` images are noted as style references but primary settings capability belongs to Phase 6 scope.

</deferred>

---

*Phase: 04-display-modes*
*Context gathered: 2026-02-14*
