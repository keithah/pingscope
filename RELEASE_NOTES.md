# PingScope 0.5.0

PingScope 0.5.0 makes continuous monitoring lighter, adds a true All Hosts experience on iPhone, and hardens history and iCloud synchronization for long-running use.

## Battery and CPU

- Added adaptive idle backoff so probes consume less power when the app is monitoring quietly in the background.
- Fixed a macOS History loading-state latch that could leave an indeterminate spinner active and continuously relayout charts and the map at display refresh rate.
- Reduced repeated All Hosts Ring and History chart presentation work during SwiftUI updates.
- Bounded process, history, and presentation buffers so extended monitoring remains predictable.

## All Hosts and Live Activity

- Added All Hosts Signal and Ring views on iPhone with stable host ordering, status, latency, and per-host controls.
- Added Live Activities for at-a-glance monitoring, including Lock Screen and Dynamic Island presentations on supported devices.
- Improved multi-host session coordination and history navigation while preserving existing probe behavior.

## Sync and history reliability

- Hardened CloudKit account recovery, retry backoff, record accumulation, and terminal-record handling.
- Batched large remote history backfills into retry-safe SQLite transactions.
- Preserved legitimate out-of-retention CloudKit backfills delivered in the current batch while still pruning older stored data.
- Streamed weekly digest input and expanded bounded memoization to avoid unnecessary full-history materialization.

## Internal

- Split Widget and Live Activity support into lean extension modules; extension binaries no longer link the full core, iOS, or history modules.
- Reorganized tests by module and added build-graph guards for extension linkage, release version consistency, signing-profile embedding, and release tooling.
- Developer ID release tooling now requires, validates, and embeds a non-expired CloudKit provisioning profile before signing.
- Sparkle tools are discovered automatically from Xcode-resolved build artifacts.
- Version: 0.5.0
- Build: 89

Publishing, tagging, notarization, Sparkle feed updates, TestFlight submission, and App Store submission are intentionally not part of this preparation commit.
