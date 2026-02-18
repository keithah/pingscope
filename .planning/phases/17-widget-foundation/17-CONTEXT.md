# Phase 17: Widget Foundation - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

macOS WidgetKit integration displaying live ping status in desktop widgets and Notification Center. Widgets show cached data from main app via shared UserDefaults. Three widget sizes (small/medium/large) covering single host, multi-host summary, and full host list. Interactive behavior limited to tapping to open app.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

User has granted full design discretion for this phase. Research and planning agents should:

- **Visual presentation**: Choose appropriate layout density, color coding scheme, typography, and status indicators based on macOS WidgetKit design patterns and system conventions
- **Information hierarchy**: Determine what data shows in each widget size based on available space and importance (latency, packet loss, timestamp, host names)
- **Host selection logic**: Decide which hosts appear in medium widget (3 hosts) — priority based on status/importance/user configuration
- **Stale data handling**: Define visual treatment for stale data (>15min old) — dimming, graying, badge, or other indicator
- **Status color scheme**: Choose colors for good/warning/critical states — should follow macOS system colors and accessibility guidelines
- **Update timing**: Respect WidgetKit budget (40-70 updates/day) while balancing freshness
- **Dark mode support**: Ensure proper contrast and readability in both light and dark appearances

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

Researcher should investigate:
- WidgetKit best practices for macOS Sequoia
- System color conventions for status indicators
- Typical update patterns for monitoring widgets
- App Group entitlement configuration requirements

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

(Future widget enhancements documented in REQUIREMENTS.md Future section)

</deferred>

---

*Phase: 17-widget-foundation*
*Context gathered: 2026-02-17*
