# Host Identity Palette Design

## Goal

Make host colors in the iOS All Hosts experience more distinctive while preserving stable host identity across views and launches.

## Scope

The change applies to every iOS surface that consumes `PingScopeIOSHostIdentityPalette`:

- All Hosts concentric rings and their legend
- All Hosts multi-series latency graphs

Focused-host health rings remain status-colored and are not host-identity surfaces. Health and diagnosis colors are unchanged.

This work does not change probe or network protocols, retention, graph-downsampling math, cache-key fingerprints, host ordering, ring progress, or status semantics.

## Palette

Replace the current six system-color tokens with twelve curated identity tokens. Each token has explicit light- and dark-appearance RGB values derived from the approved “Curated 12-color palette” direction.

The palette should emphasize separation in both hue and luminance. It may use colors near health hues because identity is reinforced by the matching legend and graph series, but token values must remain visually distinguishable from adjacent palette entries on both supported appearances.

Token names should describe their visual family rather than their position. The implementation should keep the token-to-color mapping centralized so rings and graphs cannot drift.

## Assignment and Migration

Continue deriving the palette index deterministically from the host UUID. Do not persist a separate color assignment.

Increasing the palette count from six to twelve intentionally causes a one-time remap for some existing hosts. After the update, each host remains stable across launches, saved-order changes, ring/graph navigation, and any other consumer of the shared palette.

The larger palette makes exact collisions materially less likely but does not claim to guarantee unique colors for every simultaneously visible host. Guaranteeing collision-free visible colors would make colors dependent on presentation order and conflict with the stable-identity requirement.

## Architecture

`PingScopeIOSHostIdentityPalette.ColorToken` remains the platform-neutral identity token. `PingScopeIOSHostIdentityPalette.color(for:)` and `color(at:)` remain the only assignment functions.

The SwiftUI adapter owns adaptive rendering. Every token maps to explicit light and dark RGB components and resolves through the current interface style. Both `PingScopeIOSRingViews` and `PingScopeIOSGraphViews` continue consuming the same adapter.

No view independently selects or modifies an identity hue beyond opacity used for background tracks.

## Accessibility

- Supply separate light and dark values rather than relying on one RGB value for both appearances.
- Preserve the existing legend text, host labels, health text, and accessibility labels; color is not the only source of identity or status.
- Do not repurpose identity colors as health semantics.
- Manually inspect representative four-ring and graph-series combinations in light and dark appearances.

## Testing

Add tests that verify:

- the shared palette exposes exactly twelve tokens;
- UUID assignment is deterministic;
- negative and overflow indices normalize safely;
- ring and graph presentation derive identity from the same token;
- every token has explicit light and dark rendering components;
- representative UUIDs exercise palette indices beyond the original six-token range.

The implementation should begin with a behavioral RED that demonstrates the current six-token shipping path cannot provide the approved expanded identity set. Tests must exercise the shared production palette used by rings and graphs, not a parallel test-only helper.

Run the existing Swift package tests, iOS simulator build, macOS build, iOS validation, app smoke validation, and diff/design-tree checks after implementation.

## Release Handling

The source version remains 0.5.0 unless separately changed. Build 91 is already uploaded and cannot be replaced; any TestFlight upload containing this palette change requires build 92 or later. Implementation and verification do not themselves authorize an upload, tag, push, GitHub release, or other publication.
