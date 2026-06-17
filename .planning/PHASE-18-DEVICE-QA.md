# Phase 18 Device QA

These checks require a physical iPhone because Live Activities, Dynamic Island/Lock Screen behavior, local-network privacy prompts, and iOS background runtime are not fully validated by simulator builds.

## Setup

- Install a fresh `PingScope-iOS` build from Xcode or TestFlight.
- Use a host with public reachability, such as Cloudflare DNS on TCP port `443`.
- Use a local host, such as the default gateway, for local-network permission checks.
- Keep Console.app open with the iPhone selected if detailed runtime logs are needed.

## Device Smoke Status

Physical-device build/install/launch smoke passed on `pHADM`.

- Device: `pHADM`, iPhone 16 Pro / `iPhone17,1`, iOS `26.5`.
- Pairing: available, Developer Mode enabled, wired.
- Build: `PingScope-iOS` Debug built with automatic development provisioning.
- Install/launch: `devicectl` installed and launched `com.hadm.PingScope`.
- Process check: `PingScope.app/PingScope` was visible in `devicectl device info processes`.

The iOS App Group entitlement was removed from the iOS app and Live Activity targets because the current iOS implementation does not use shared-container storage and automatic provisioning could not use the unavailable group identifier.

## Checks

- Launch the app and confirm continuous foreground monitoring starts without pressing a duration button.
- Start explicit `30s` and `1m` sessions while the app is foregrounded.
- Confirm the app graph, latency, stats, countdown, and recent history update during the session.
- Confirm a Live Activity appears on the Lock Screen or Dynamic Island where supported.
- Background the app and confirm updates continue only while iOS grants finite runtime.
- Confirm the Live Activity ends or becomes stale when a selected finite duration completes or iOS expires background runtime.
- Start a `1m` session and confirm it completes in foreground.
- Background a `1m` session and confirm early expiration is handled without presenting stale latency as current.
- Select a local host and confirm iOS asks for local-network access only when needed.
- Deny local-network access and confirm the app shows failure state without crashing.
- Allow local-network access and confirm local host monitoring works on the next session.
- Reopen the app and confirm hosts and recent local history persisted.

## Acceptance

- No copy or behavior implies continuous always-on background iOS pinging.
- The app monitors continuously only while foregrounded, and stops probing when a finite session ends, when the user stops it, or when iOS expires background runtime.
- Live Activity state never makes old measurements look current.
- Mac schemes and SwiftPM builds remain green after iOS changes.
