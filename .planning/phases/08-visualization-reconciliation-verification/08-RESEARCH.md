# Phase 8: Visualization Requirement Reconciliation & Verification - Research

**Researched:** 2026-02-16
**Domain:** Visualization requirement reconciliation, implementation gap closure, and phase verification evidence for VIS-01..VIS-07
**Confidence:** HIGH

## Summary

Phase 8 is a reconciliation-and-proof phase, not a greenfield visualization build. The codebase already contains the core visualization implementation in `DisplayGraphView`, `DisplayViewModel`, `FullModeView`, and `RecentResultsListView`, and Phase 5 execution summaries indicate intended completion. The milestone gap exists because VIS-01..VIS-07 remain `Pending` in traceability and Phase 5 has no verification artifact.

The standard approach for this phase is: (1) reconcile each VIS requirement against current code and runtime behavior, (2) implement only the minimum missing behavior needed for strict requirement alignment, (3) produce a Phase 5 verification report in the established verifier format, and (4) update `.planning/REQUIREMENTS.md` traceability to `Complete` for VIS-01..VIS-07 with evidence-backed confidence.

A likely reconciliation hotspot is VIS-04 wording versus current history presentation. Requirement text asks for timestamp, host, ping time, and status; the current full-mode header shows `TIME`, `HOST`, `STATUS`, while ping time is embedded in status text (`"42ms"` / `"Failed"`). Plan Phase 8 as strict reconciliation: either add an explicit ping-time column + status column, or document and get explicit acceptance that current combined status cell satisfies VIS-04.

**Primary recommendation:** Execute Phase 8 as a requirements-evidence pass with a strict VIS-by-VIS matrix; treat VIS-04 as a probable implementation gap and resolve it before marking traceability complete.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI (`View`, `Canvas`, `ScrollView`, `LazyVStack`, `Menu`) | Apple platform framework (macOS 13 target) | Visualization UI (graph/history/time filter/stats) | Already implemented and wired in production views; no extra dependency risk |
| Foundation + Combine | Apple platform framework | Date/time filtering, state publication, formatting | Existing `DisplayViewModel` data pipeline depends on this stack |
| XCTest | Xcode/SwiftPM test framework | Regression checks for `DisplayViewModel` sample retention/order | Existing tests already cover bounded history behavior |
| Markdown verification artifacts under `.planning/phases/*/*-VERIFICATION.md` | Repo convention | Audit-grade requirement evidence | Existing phases 01/02/03/04/06/07 use this format successfully |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Package Manager (`swift-tools-version: 5.9`) | 5.9 | Build/test orchestration and reproducible tooling | For static validation and targeted tests during reconciliation |
| AppKit (`NSWindow`, menu bar shell) | Apple platform framework | Runtime host display shell and update loop context | When evidence needs end-to-end runtime proof |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Existing SwiftUI graph/list surfaces | New chart/table library | Unnecessary scope and risk for a reconciliation phase |
| Phase verification document | Only plan summaries + checklist notes | Fails milestone audit expectation for `*-VERIFICATION.md` evidence |
| Requirement-by-requirement reconciliation | Global "looks good" statement | Not auditable; cannot justify per-requirement traceability updates |

**Installation:**
```bash
# No new dependencies required.
swift test
```

## Architecture Patterns

### Recommended Project Structure
```
.planning/
├── REQUIREMENTS.md                                  # traceability source of truth
└── phases/
    ├── 05-visualization/
    │   └── 05-visualization-VERIFICATION.md        # create in Phase 8
    └── 08-visualization-reconciliation-verification/
        └── 08-RESEARCH.md

Sources/PingScope/
├── ViewModels/DisplayViewModel.swift               # filtering/order/retention + graph/history projections
└── Views/
    ├── DisplayGraphView.swift                      # VIS-01/02 graph rendering
    ├── FullModeView.swift                          # VIS-03/04/06/07 user surface
    └── RecentResultsListView.swift                 # VIS-04/05 history rows
```

### Pattern 1: Requirement-to-Evidence Reconciliation Matrix
**What:** Build a strict VIS-01..VIS-07 table mapping requirement -> code evidence -> runtime evidence -> pass/fail.
**When to use:** First step in Phase 8, before any code edits or traceability updates.
**Example:**
```markdown
| Requirement | Code Evidence | Runtime Verification | Status |
|-------------|---------------|----------------------|--------|
| VIS-01 | `Sources/PingScope/Views/DisplayGraphView.swift:89` areaFill + `:93` linePath stroke | Open full mode; confirm line + gradient fill while pings update | PASS |
| VIS-04 | `Sources/PingScope/Views/FullModeView.swift:240` headers + `Sources/PingScope/Views/RecentResultsListView.swift:33` row rendering | Verify visible timestamp/host/ping/status fields in history table | GAP/PASS |
```

### Pattern 2: Fix-Then-Verify (Only for Confirmed Gaps)
**What:** Apply minimal code changes only where reconciliation finds objective requirement mismatch.
**When to use:** After matrix identifies a gap (likely VIS-04 column semantics).
**Example:**
```swift
// Source: Sources/PingScope/Views/RecentResultsListView.swift
// Keep recent-first and scroll behavior; change presentation only if needed
// to expose explicit ping-time and status fields for VIS-04.
ScrollView {
    LazyVStack(spacing: compact ? 2 : 4) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            rowView(row)
        }
    }
}
```

### Pattern 3: Verification Artifact as Audit Contract
**What:** Produce a Phase 5 verification report in the same structure used by other completed phases.
**When to use:** After all VIS requirements are pass-verified.
**Example:**
```markdown
---
phase: 05-visualization
verified: 2026-02-16Txx:xx:xxZ
status: passed
score: 7/7 must-haves verified
---

## Requirements Coverage
| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| VIS-01 | ✓ SATISFIED | None |
...
| VIS-07 | ✓ SATISFIED | None |
```

### Anti-Patterns to Avoid
- **Marking traceability first:** Do not set VIS rows to `Complete` before evidence and verification report are finalized.
- **Broad refactor during reconciliation:** Keep scope to requirement alignment and proof artifacts.
- **Ambiguous VIS-04 interpretation:** Resolve ping-time/status semantics explicitly; do not leave interpretation implicit.
- **Single-source evidence:** Use both static code references and runtime/human checks for UI truths.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Requirement tracking | Custom sidecar tracker file | `.planning/REQUIREMENTS.md` traceability table | Existing single source of truth used by audits |
| Visualization rewrite | New graph/history components for Phase 8 | Existing `DisplayGraphView` + `RecentResultsListView` + `DisplayViewModel` | Phase objective is reconciliation, not redesign |
| Verification format | Ad-hoc narrative notes | Existing phase verification report schema (`Observable Truths`, `Required Artifacts`, `Requirements Coverage`) | Consistency with prior verifier artifacts and audit parsing |
| Runtime proof strategy | Fully automated-only assertion for all UI truths | Mixed static + human verification checkpoints | Visual behavior and usability need runtime confirmation |

**Key insight:** Phase 8 succeeds through evidence discipline and minimal targeted fixes, not new architecture.

## Common Pitfalls

### Pitfall 1: VIS-04 Column Ambiguity
**What goes wrong:** History row is treated as compliant even if ping time and status are conflated in one visual field.
**Why it happens:** Requirement asks for four fields; implementation currently labels three headers.
**How to avoid:** Use strict acceptance criteria: timestamp, host, ping time, and status must each be explicitly represented (or explicitly accepted as combined with documented rationale).
**Warning signs:** Verification report struggles to point to distinct ping-time vs status evidence.

### Pitfall 2: Traceability Updated Without Verification Artifact
**What goes wrong:** VIS rows are set to `Complete` without creating a Phase 5 `*-VERIFICATION.md` file.
**Why it happens:** Teams treat summaries as sufficient evidence.
**How to avoid:** Gate traceability update behind completed verification artifact.
**Warning signs:** `.planning/phases/05-visualization` still lacks `*-VERIFICATION.md`.

### Pitfall 3: Relying on Full `swift test` as Sole Gate
**What goes wrong:** Phase appears blocked by known cross-phase test wiring failures unrelated to VIS logic.
**Why it happens:** Milestone audit already flags regression wiring issues (Phase 9 scope).
**How to avoid:** Use targeted visualization evidence for Phase 8 acceptance; record global test-suite limitation as a known risk/dependency.
**Warning signs:** Failures in `StatusItemTitleFormatterTests` or `ContextMenuFactory` signature mismatch dominate verification output.

### Pitfall 4: Breaking Shared DisplayViewModel Behavior
**What goes wrong:** Gap fixes regress preserved host/time range behavior across mode switches.
**Why it happens:** Touching view-model projections without honoring Phase 4 decisions.
**How to avoid:** Preserve one shared `DisplayViewModel`, bounded per-host buffers, and recent-first projections.
**Warning signs:** Host/time selection resets when toggling compact/full.

## Code Examples

Verified patterns from current project implementation:

### Graph Fill + Per-Ping Points (VIS-01, VIS-02)
```swift
// Source: Sources/PingScope/Views/DisplayGraphView.swift
areaFill(in: size, xBounds: xBounds, yBounds: yBounds)

linePath(in: size, xBounds: xBounds, yBounds: yBounds)
    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

dataPointDots(in: size, xBounds: xBounds, yBounds: yBounds)
```

### Time Filter Window Projection (VIS-03)
```swift
// Source: Sources/PingScope/ViewModels/DisplayViewModel.swift
private func filteredSamples(for hostID: UUID?) -> [HostSample] {
    guard let hostID,
          let hostSamples = samplesByHostID[hostID]
    else {
        return []
    }

    let cutoff = Date().addingTimeInterval(-selectedTimeRange.windowDuration)
    return hostSamples.filter { $0.timestamp >= cutoff }
}
```

### Recent-First Scrollable History Projection (VIS-05)
```swift
// Source: Sources/PingScope/ViewModels/DisplayViewModel.swift
let rows = filteredSamples(for: hostID)
    .reversed()
    .map {
        RecentResultRow(timestamp: $0.timestamp, latencyMS: $0.latencyMS, hostName: hostName)
    }
```

### Stats Calculation (VIS-06, VIS-07)
```swift
// Source: Sources/PingScope/Views/FullModeView.swift
let transmitted = results.count
let received = results.filter { $0.latencyMS != nil }.count
let lossPercent = transmitted > 0 ? Double(transmitted - received) / Double(transmitted) * 100 : 0

let latencies = results.compactMap(\.latencyMS)
let minLatency = latencies.min() ?? 0
let maxLatency = latencies.max() ?? 0
let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
let stddev = latencies.isEmpty ? 0 : sqrt(latencies.map { pow($0 - avgLatency, 2) }.reduce(0, +) / Double(latencies.count))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 5 completion inferred from plan summaries only | Explicit verifier artifact + requirement traceability closure | Milestone audit on 2026-02-16 | Enables auditable completion for VIS requirements |
| Basic graph line without full polish | Gradient fill + per-sample markers in `DisplayGraphView` | Phase 5 plan 05-02 (2026-02-15) | VIS-01/VIS-02 implementation evidence exists, needs formal verification closure |
| 360-sample retention | 3600 per-host sample retention | Phase 5 plan 05-01 (2026-02-15) | 1-hour filter viability materially improved for VIS-03/VIS-05 |

**Deprecated/outdated:**
- Using only `*-SUMMARY.md` as phase acceptance evidence is outdated for milestone closure; use `*-VERIFICATION.md`.

## Open Questions

1. **Does VIS-04 require explicit separate ping-time and status columns?**
   - What we know: Requirement text says timestamp + host + ping time + status; current UI header is TIME/HOST/STATUS with latency text embedded.
   - What's unclear: Whether combined status cell is acceptable for milestone sign-off.
   - Recommendation: Plan for explicit separation unless user provides acceptance for combined representation.

2. **Which verification filename should be canonical for Phase 5?**
   - What we know: Existing phases use `*-VERIFICATION.md` with mixed naming conventions (`04-VERIFICATION.md`, `07-settings-VERIFICATION.md`).
   - What's unclear: Preferred canonical filename for Phase 5 artifact.
   - Recommendation: Use `05-visualization-VERIFICATION.md` for consistency with most phase folders and clear audit discoverability.

3. **Can Phase 8 require fully green global tests?**
   - What we know: Milestone audit flags unrelated compile-breakers assigned to Phase 9.
   - What's unclear: Whether Phase 8 acceptance should block on global suite.
   - Recommendation: Use targeted visualization verification in Phase 8 and document global test limitation as Phase 9 dependency.

## Sources

### Primary (HIGH confidence)
- `/.planning/ROADMAP.md` - Phase 8 goal/scope/success criteria and Phase dependencies
- `/.planning/REQUIREMENTS.md` - VIS-01..VIS-07 definitions and traceability status
- `/.planning/v1.0-v1.0-MILESTONE-AUDIT.md` - Audit gap evidence and closure targets
- `Sources/PingScope/Views/DisplayGraphView.swift` - VIS-01/VIS-02 rendering behavior
- `Sources/PingScope/ViewModels/DisplayViewModel.swift` - Time-window filtering, bounded retention, recent-first projections
- `Sources/PingScope/Views/FullModeView.swift` - Time filter menu, history headers, stats surface
- `Sources/PingScope/Views/RecentResultsListView.swift` - Scrollable history rendering behavior
- `Tests/PingScopeTests/DisplayViewModelTests.swift` - Retention/order regression evidence

### Secondary (MEDIUM confidence)
- `/.planning/phases/05-visualization/05-01-SUMMARY.md` - Recorded intent/outcomes for retention work
- `/.planning/phases/05-visualization/05-02-SUMMARY.md` - Recorded intent/outcomes for graph polish
- `/.planning/phases/05-visualization/05-03-SUMMARY.md` - Human checkpoint approval note

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - In-repo stack is explicit (`Package.swift`, source imports) and unchanged for this phase.
- Architecture: HIGH - Existing verification artifact patterns and phase scope are well-established in repo docs.
- Pitfalls: HIGH - Directly derived from audit findings and current implementation details.

**Research date:** 2026-02-16
**Valid until:** 2026-03-18 (30 days - stable internal process and stack)
