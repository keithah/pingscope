# Bold Utility Palette and Settings Cleanup Design

## Goal

Make host identity colors vivid and immediately distinguishable throughout the iOS app, and remove the low-value Session status block from Monitor settings.

## Palette

Keep the existing twelve `PingScopeIOSHostIdentityPalette.ColorToken` cases, order, stable UUID hashing, and identity assignments. Change only their light- and dark-appearance RGB values:

| Token | Light | Dark |
| --- | --- | --- |
| cobalt | `#0068D9` | `#278DFF` |
| magenta | `#D91D5B` | `#FF3D7F` |
| teal | `#008C78` | `#00D1B2` |
| violet | `#6D28D9` | `#9B6CFF` |
| gold | `#B77900` | `#FFC400` |
| orange | `#D95F00` | `#FF8A00` |
| seaGreen | `#00835D` | `#00C896` |
| purple | `#8C22C7` | `#C54CFF` |
| azure | `#0077B6` | `#00B8F5` |
| crimson | `#C91E3A` | `#FF4560` |
| olive | `#568A00` | `#8FD400` |
| bronze | `#A85D00` | `#EFA33A` |

The shared palette remains the single source for multi-host graphs, focused graphs, concentric rings, legends, host dots, mini-graphs, and peer rows. Semantic health colors for Healthy, Degraded, Down, and No Data remain unchanged.

No one-time remap is required because token order and stable host-to-index mapping do not change. Existing hosts retain their identity slot and receive the new color for that slot.

## Settings Cleanup

Remove the entire `Section("Session")` block from Monitor settings, including the phase text (`Live`, `Stale`, or `Ended`) and duration text (`App open` or a countdown). Session controls on the Monitor screen remain unchanged.

Remove the now-unused settings-only `remainingText` view property if it has no other consumer.

## Testing and Verification

- Start with behavioral RED assertions against the current RGB values and current Session-section source/rendering path.
- Assert all twelve exact light and dark RGB values.
- Preserve tests for twelve deterministic buckets, integer normalization, stable UUID mapping, and graph/ring identity agreement.
- Assert the shipping settings view no longer renders the Session section or consumes `remainingText`.
- Run focused presentation/build-graph tests, the full Swift suite, and the iOS simulator build.
- Visually inspect a four-host graph, rings, legend, dots, and mini-graphs in both light and dark appearances.

## Non-goals

- Do not change health thresholds, semantic status colors, host hashing, token order, graph math, probing, network behavior, retention, app versions, or build numbers.
- Do not touch `design/`.
- Preserve the existing uncommitted peer-latency work until it is intentionally committed with its own scope.
