# Synced Host Colors, Multi-Host Widget, and Live Activity Controls

Date: 2026-07-21

## Goal

Make host identity consistent and user-controlled across PingScope, show every supported host series in the widget and Switch Host sheet, add honest Live Activity presentation controls, and ship the previously corrected iOS default-gateway behavior in the same device build.

## Scope

This change covers:

- An optional, arbitrary opaque sRGB color for each host.
- CloudKit synchronization of that color with the existing host record.
- An Automatic color choice that restores the deterministic Bold Utility assignment.
- Consistent use of the resolved host color in iOS and macOS graphs, rings, keys, dots, latency text, Switch Host rows, widgets, and Live Activities where host identity color is presented.
- The existing medium widget composition with two to five independent colored latency lines and a compact key across the top.
- A maximum of five displayed widget hosts, selected from the first five enabled hosts in saved Hosts order.
- Switch Host rows with the same identity color, mini-graph, and latest latency treatment used elsewhere.
- Separate settings rows under a Live Activity header for Lock Screen Live Activity and Dynamic Island Details.
- Rejection of `169.254/16` link-local addresses as default-gateway candidates while retaining automatic gateway refresh on satisfied network-path changes.

This change does not alter probe/network wire protocols, sample retention windows, graph-downsampling math, or probe-configuration cache fingerprints.

## Host appearance model and sync

`HostConfig` gains an optional presentation-only color value represented as opaque sRGB red, green, and blue components. A missing value means Automatic. Existing JSON remains decodable because the field is optional and defaults to nil when absent.

The existing CloudKit monitored-host record stores `HostConfig` as JSON, so the color follows the existing host synchronization, conflict, and deletion lifecycle without introducing a second CloudKit record type. Host color changes count as host presentation edits for sync, but they do not change probe configuration identity, restart probes, or invalidate session samples.

A single host-color resolver returns either:

1. the valid custom sRGB color stored on the host, or
2. the existing deterministic Bold Utility color derived from the host UUID.

Invalid, non-finite, or out-of-range decoded components fall back to Automatic. The editor writes fully opaque colors; alpha is not stored or honored because transparency makes graph and accessibility contrast unpredictable.

Host-color resolution must be shared by every production surface rather than reimplemented by the widget or individual views.

## Host editing and ordering

Host Edit adds an Appearance section with:

- Apple’s full color picker, normalized to opaque sRGB.
- A visible preview of the resolved color.
- “Use Automatic Color,” which clears the custom value and restores the deterministic Bold Utility assignment.

The existing Hosts reorder controls remain unchanged. Saved Hosts order is authoritative for:

- multi-host graph, ring, and legend order;
- Switch Host order;
- widget key and line order; and
- the first five enabled hosts selected for widget display.

If more than five hosts are enabled, PingScope still monitors all of them; only the widget presentation is capped. Users control the visible five by reordering Hosts.

## Widget presentation

The medium widget keeps its current composition and proportions. The existing top host summaries become the graph key and support two through five hosts. Each key item contains:

- the host’s resolved identity-color dot;
- a single-line, compressible/truncatable host name; and
- the latest latency or failure text.

The graph below the key draws one independent line per displayed host in the matching identity color. All series use the same time window and y-axis scale so their latency is visually comparable. Empty or failure-only series do not fabricate a line; their key entry remains visible with the appropriate unavailable/failure label.

The Live/Stale status badge stays in its current location. The widget must preserve its existing stale treatment and timeline policy.

Large widgets use the same resolved colors and multi-series graph data. Small-widget behavior remains governed by its current family policy; this design does not force a graph into a family that does not currently support one.

The widget snapshot carries each host’s resolved color and enough per-host sample identity to group samples into independent series. Decoding remains backward compatible: an older snapshot without color uses Automatic.

## Switch Host presentation

The Switch Host sheet keeps All Hosts first and preserves saved Hosts order. Each concrete host row uses the standard reusable host-row presentation:

- resolved identity-color dot and text accents;
- host name and endpoint;
- compact mini-graph using that host’s samples; and
- latest latency, failure, or unavailable value.

The selected host keeps the existing checkmark behavior. Cached peer measurements remain explicitly cached and never become live health. Rows without samples remain visible without inventing latency or graph data.

## Live Activity controls

Monitor Settings adds a `Live Activity` section with two rows, both disabled by default:

- `Lock Screen Live Activity`: the master ActivityKit preference. Turning it off ends any current Live Activity and prevents future requests. Because ActivityKit owns both system surfaces, disabling this preference also removes the Dynamic Island activity.
- `Dynamic Island Details`: controls PingScope’s rich Dynamic Island presentation while the master preference remains enabled. Turning it off reduces the Island to the minimum system presence that ActivityKit permits; it does not claim to remove a system-owned surface independently.

The Dynamic Island row is disabled when the master preference is off. Enabling the master permits the next active monitoring session/update to request a Live Activity. Preferences persist locally and require explicit opt-in.

The settings copy must make the dependency clear and must not promise independent system behavior that ActivityKit does not provide.

## Default gateway correction

The iOS gateway detector must never derive a router address from a self-assigned `169.254/16` interface. It continues to accept RFC 1918 addresses and derive the likely `/24` gateway used by the existing implementation.

The existing `NWPathMonitor` handler remains the trigger: on every satisfied path update it runs gateway detection and updates the existing Default Gateway host when the address changes. Updating the address preserves the host UUID, custom color, settings, enabled state, notification policy, and saved order. It reconciles the active monitoring scope through the existing lifecycle path.

If no valid private candidate is available during a transient handoff, PingScope does not replace the saved gateway with a link-local value. A later satisfied path update with a valid private address performs the update.

## Data flow

1. Host Edit resolves and previews the current color.
2. Save writes the optional custom sRGB value into `HostConfig`.
3. Existing host persistence and CloudKit JSON sync distribute the edit.
4. App presentation resolves custom-or-Automatic color once per host and uses it for every graph, ring, key, row, and Live Activity model.
5. Widget publishing includes saved-order hosts, resolved colors, health, and host-tagged samples.
6. Widget rendering takes the first five enabled hosts, builds a compact key, groups samples by host, applies a shared graph scale, and draws up to five colored paths.

## Error handling and compatibility

- Legacy hosts and snapshots without color decode as Automatic.
- Malformed custom colors fall back to Automatic rather than failing host or widget decoding.
- A host with no samples remains in keys and lists with unavailable text and no fabricated graph.
- More than five enabled hosts are monitored normally; the widget deterministically uses the first five.
- CloudKit unavailable/off behavior remains unchanged; local color edits persist through the normal host store and sync later if enabled.
- Turning off the Live Activity master ends current content safely through the existing ActivityKit ownership/lifecycle coordinator.

## Testing strategy

Behavioral RED tests must precede each production change and fail for the intended shipping behavior rather than missing symbols alone.

Required coverage:

- Legacy `HostConfig` JSON decodes with Automatic color.
- Custom sRGB color round-trips through host persistence and CloudKit monitored-host record mapping.
- Invalid color components fall back to Automatic.
- Color-only edits are presentation metadata and do not change probe configuration identity or restart the coordinator.
- The resolver uses custom color when present and deterministic Bold Utility when Automatic.
- Graph, ring, legend, rows, Switch Host, widget, and Live Activity presentation models resolve the same color for a host.
- Host Edit saves a custom picker value and clears it through Use Automatic Color.
- Reordering Hosts changes Switch Host and widget key/line order without changing host identity.
- Widget selection caps at five enabled hosts in saved order while monitoring retains all enabled hosts.
- Widget graph preparation produces one independent series per visible host on a shared window/scale, including two-, three-, four-, and five-host cases.
- Widget failure/empty-series behavior never fabricates paths or latency.
- Switch Host rows expose latest latency and mini-graph data and preserve cached/unavailable semantics.
- Lock Screen Live Activity defaults off, persists opt-in, blocks requests when off, and ends an existing activity.
- Dynamic Island Details defaults off, persists independently, is disabled by the master preference, and selects rich versus minimal presentation without claiming to remove the system surface.
- Gateway detector rejects `169.254/16`, accepts RFC 1918 candidates, and the app’s network-path shipping wiring continues to refresh and replace the gateway host while preserving identity/order/color.

Final verification includes focused suites, the full Swift test suite, iOS Simulator build, signed physical-device build, install/launch, and visual inspection of light/dark widget, Switch Host, Host Edit, and Live Activity settings. No TestFlight upload occurs until the physical-device build is approved.

## Acceptance criteria

- The current widget layout shows two to five independently colored host lines and an unambiguous matching key.
- The first five enabled hosts in saved order control widget contents; all enabled hosts continue monitoring.
- Users can select any opaque custom color, reset to Automatic, and see the choice sync between iPhone and Mac.
- Every production identity-color surface agrees for the same host.
- Switch Host shows each host’s graph and current/cached latency just like the standard host rows.
- Hosts remains reorderable and ordering propagates everywhere specified.
- Lock Screen Live Activity and Dynamic Island Details appear as separate, truthful settings under a Live Activity header.
- A `169.254.x.x` address can no longer become Default Gateway, and valid gateway changes update automatically while preserving host presentation metadata.
