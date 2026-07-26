## PingScope 0.5.3

Critical fix plus quality-of-life improvements:

- **Fixed a crash when enabling iCloud Sync** in Developer ID (DMG) builds — the app was missing entitlements that App Store builds receive automatically, so CloudKit aborted on activation
- Host addresses are now clickable: click to copy (with inline confirmation), right-click to copy or open — in the overlay, the popover captions, and the All Hosts rows
- The overlay's single-host ring view shows the host address instead of duplicating the menu bar latency number
- Fixed the standalone popover window's samples table not expanding when the window is resized taller
- Fixed inactive "Other Hosts" on iOS looking like live data — they now show a muted Idle badge
