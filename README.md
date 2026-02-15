# PingMonitor Documentation

This documentation describes the PingMonitor macOS menu bar application, a network latency monitoring tool that runs in the system tray.

## Overview

PingMonitor is a macOS menu bar application that monitors network connectivity by pinging configurable hosts. It displays real-time latency data, historical graphs, and provides configurable notifications for network issues.

**Key Features:**
- Menu bar status display with color-coded latency indicator
- Multiple host monitoring (Google DNS, Cloudflare DNS, Default Gateway)
- Three ping methods: ICMP (simulated via TCP), UDP, TCP
- Auto-detection of default gateway
- Real-time latency graph visualization
- 7 notification alert types
- Compact and full display modes
- Stay-on-top floating window option
- macOS Widget extension (small, medium, large)
- Data export (CSV, JSON, Text)

## Application Structure

```
PingMonitor/
├── App/
│   └── PingMonitorApp.swift          # @main entry point
├── Models/
│   ├── Host.swift                    # Host data model
│   ├── PingResult.swift              # Ping result model
│   ├── PingSettings.swift            # Per-host ping configuration
│   ├── NotificationSettings.swift    # Alert configuration
│   └── Enums.swift                   # PingStatus, PingType, GatewayMode, etc.
├── Services/
│   ├── PingService.swift             # Core ping engine
│   ├── NetworkMonitor.swift          # Gateway detection
│   ├── NotificationService.swift     # Alert management
│   └── PersistenceService.swift      # Settings storage
├── ViewModels/
│   ├── PingViewModel.swift           # Main view model
│   └── SettingsViewModel.swift       # Settings logic
├── Views/
│   ├── MenuBar/
│   │   └── MenuBarController.swift   # NSStatusItem management
│   ├── Main/
│   │   ├── ContentView.swift         # Full view
│   │   ├── CompactView.swift         # Compact view
│   │   ├── GraphView.swift           # Ping graph
│   │   └── HistoryView.swift         # Results list
│   ├── Settings/
│   │   └── SettingsView.swift        # Main settings
│   └── Export/
│       └── ExportView.swift          # Data export
└── Utilities/
    ├── Extensions.swift              # Helper extensions
    └── Constants.swift               # App constants
```

## Documentation Index

- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture and component interactions
- [MODELS.md](./MODELS.md) - Data model specifications
- [SERVICES.md](./SERVICES.md) - Service layer documentation
- [VIEWS.md](./VIEWS.md) - View layer and UI components
- [WIDGET.md](./WIDGET.md) - macOS Widget extension
- [CONFIGURATION.md](./CONFIGURATION.md) - Constants and configuration options

## Technical Requirements

- **Platform:** macOS 13.0+ (Ventura)
- **Frameworks:** SwiftUI, AppKit, Network.framework, SystemConfiguration
- **Bundle ID:** com.hadm.pingmonitor
- **App Group:** group.com.hadm.pingmonitor.shared

## Entitlements

```xml
com.apple.security.app-sandbox: true
com.apple.security.network.client: true
com.apple.security.files.user-selected.read-write: true
com.apple.security.application-groups: [group.com.hadm.pingmonitor.shared]
```

## App Store Sandbox Compatibility

The application is designed for App Store distribution. Since raw ICMP sockets require special entitlements not available in the App Store sandbox, the "ICMP" ping method actually performs TCP connections to common ports (53, 80, 443, 22, 25) as a fallback mechanism to measure connectivity latency.
