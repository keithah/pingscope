# PingScope 0.5.1

PingScope 0.5.1 reduces power use during long-running monitoring and fixes lifecycle, alerting, and synchronization edge cases found after 0.5.0.

## Battery and monitoring

- Added battery-aware adaptive monitoring on Mac and iPhone, scaling probe cadence for power source, Low Power Mode, thermal pressure, screen state, app visibility, and background execution.
- Reduced the default-gateway polling rate and coalesced cadence changes without interrupting active monitoring.
- Switched iPhone Background Keep Alive to significant-location-change monitoring to reduce background energy use.
- Fixed cadence state after closing status, Settings, and History windows.
- Hardened monitoring task ownership to avoid retained runtimes and stale lifecycle updates.

## Reliability and performance

- Fixed repeated outage alert suppression and corrected multi-failure diagnosis decisions.
- Improved CloudKit history batching and synchronization hot paths.
- Reduced repeated history, widget, and presentation work during long sessions.
- Hardened release recovery when a tag or GitHub release already exists.
- Live Activity and Dynamic Island settings default to off, so both features require explicit opt-in.

## Release

- Version: 0.5.1
- Build: 96
