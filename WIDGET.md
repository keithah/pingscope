# PingScope Widget Extension

PingScope ships a macOS WidgetKit extension from `PingScopeWidget/`. The widget reads the latest app-published latency snapshot from the shared App Group defaults store and supports small, medium, and large widget families.

## App Group

- App Group: `6R7S5GA944.group.com.hadm.PingScope`
- Current snapshot key: `PingScopeWidgetSnapshot`
- Legacy compatibility key: `widgetData`
- Main app writer: `Sources/PingScopeCore/WidgetSnapshot.swift`
- Widget reader: `PingScopeWidget/PingScopeWidgetProvider.swift`

The main app performs all network measurement. Widgets only render cached data and never probe the network directly.

## Build And Validate

Build the Xcode app product with the embedded widget extension:

```bash
scripts/build-xcode-app-bundle.sh debug /Applications developer-id
```

Run the widget bundle/shared-data validator:

```bash
scripts/validate-widget-bundle.sh /Applications/PingScope.app
```

Run the full roadmap validation suite:

```bash
scripts/validate-roadmap.sh
```

The validator checks:
- `PingScope.app/Contents/PlugIns/widgetExtension.appex` exists.
- The extension declares `com.apple.widgetkit-extension`.
- App and widget entitlements include the shared App Group.
- The widget extension is sandboxed.
- Shared defaults contain both the current and legacy widget payloads.

## Runtime Behavior

- Small widget: primary host status and latency.
- Medium widget: multi-host summary.
- Large widget: broader host/status view.
- Stale data: widget views dim old payloads after the configured stale window.
- Tap behavior: widgets use `pingscope://open` to bring PingScope forward.

## Limits

Apple’s Widget Gallery placement and light/dark visual inspection are still system UI checks. The repo now automates every local code/package/data condition that can be checked reliably from scripts; final visual inspection in Widget Gallery remains manual release QA.
