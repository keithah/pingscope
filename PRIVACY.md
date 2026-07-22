# PingScope Privacy Policy

PingScope is a local network latency monitor for macOS, with an iOS companion app. It does not require an account and does not collect, sell, or share personal information.

PingScope stores app settings, configured hosts, recent samples, local history, overlay position, notification preferences, and optional widget snapshots locally on your device. If widget support is enabled, PingScope writes a small status snapshot to its App Group container so the widget can display current network status.

PingScope uses network access only to measure the hosts you configure, detect network status, and check for updates in Developer ID builds. App Store builds do not include Sparkle update checks. Notification permission is used only for alerts you enable. On iOS, the optional Background Keep Alive setting requests Always Location permission solely to keep monitoring active in the background while a session is running; the setting is disabled by default. History samples may be labeled with the active network — the connection type (Wi-Fi, cellular, or wired), a VPN indicator, and, on cellular, the radio type (for example 5G or LTE). The Wi-Fi network name (SSID) requires the Access WiFi Information capability and location permission and is recorded only when you have granted them. When you separately enable History map tagging, approximate coordinates may also be stored with local history samples.

While iCloud Sync is off, PingScope never transmits history or host settings off your device automatically. History (including any stored coordinates, network name, and network labels) stays local unless you explicitly share an export. Cross-device iCloud Sync is off by default and starts only after your explicit opt-in. When enabled, PingScope automatically syncs retained history and host settings—including coordinates or network names already present in a stored sample—through your own private iCloud database to your devices. Turning sync off stops that activity; it is never shared with anyone else.

The iOS `remote-notification` background mode and CloudKit entitlements exist solely to receive change notifications for that opt-in private-database sync. They are inert while iCloud Sync is off and do not upload history, host settings, or any other records without the toggle enabled.

PingScope does not operate a server for analytics, tracking, advertising, or telemetry. Data exported from PingScope stays wherever you save it.

For support or privacy questions, open an issue at:

https://github.com/keithah/pingscope/issues
