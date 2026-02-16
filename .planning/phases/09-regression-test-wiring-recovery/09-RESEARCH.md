# Phase 9: Regression Test Wiring Recovery - Research

**Researched:** 2026-02-16
**Domain:** Swift Package Manager test compilation, XCTest signature alignment, and regression verification flow
**Confidence:** HIGH

## Summary

Phase 9 is a test wiring recovery phase focused on restoring compile-green automated regression tests. The milestone audit identified three specific compilation failures blocking the test suite:

1. **StatusItemTitleFormatterTests.swift:5** - References `StatusItemTitleFormatter` type that no longer exists in production code. The formatting logic was inlined into `MenuBarViewModel.formatLatencyText()`.

2. **ContextMenuFactoryTests.swift:44,87** and **MenuBarIntegrationSmokeTests.swift:39** - Call `ContextMenuActions.init()` without the required `onOpenAbout` parameter that was added when "About PingScope" menu item was introduced to `ContextMenuFactory`.

The standard approach is: (1) fix or remove stale test code to align with current production interfaces, (2) verify targeted compilation and test execution, (3) run full regression suite, and (4) produce before/after evidence with explicit command invocations and outcomes.

**Primary recommendation:** Fix the three stale test files by either removing the obsolete `StatusItemTitleFormatterTests` (since its behavior is now covered by `MenuBarViewModelTests`) or creating a minimal production type if the tests provide unique coverage, and add the missing `onOpenAbout` parameter to all `ContextMenuActions` initializer calls in tests.

## Standard Stack

The established tools for this domain:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Swift Package Manager | 5.9 (swift-tools-version) | Build orchestration, test compilation, test execution | Project already uses SPM exclusively; no Xcode project |
| XCTest | Xcode/SwiftPM bundled | Unit and integration test framework | Existing test suite uses XCTest exclusively |
| `swift build --build-tests` | SPM CLI | Compile main + test targets without running | Fast feedback for wiring fixes before full test run |
| `swift test` | SPM CLI | Run full regression suite | Canonical verification command for local and CI |
| `swift test --filter` | SPM CLI | Run specific test case or method | Targeted iteration during fix development |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `swift test --skip` | SPM CLI | Skip specific tests during iteration | If a test is temporarily blocked while fixing others |
| `swift test --parallel` | SPM CLI | Parallel test execution | Speed up full regression runs (default in SPM) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `swift test` | `xcodebuild test` | Adds complexity; SPM is simpler for this pure-Swift package |
| Removing stale tests | Creating stub types | Stubs add maintenance burden if tests provide no unique coverage |
| Manual verification | CI workflow | CI workflow exists but is release-only; local verification is sufficient for Phase 9 |

**Installation:**
```bash
# No new dependencies required
swift build --build-tests  # Verify compilation
swift test                  # Run full suite
```

## Architecture Patterns

### Recommended Project Structure
```
Tests/PingScopeTests/
├── ContextMenuFactoryTests.swift       # Needs onOpenAbout fix
├── MenuBarIntegrationSmokeTests.swift  # Needs onOpenAbout fix
├── StatusItemTitleFormatterTests.swift # Stale type reference - remove or migrate
├── MenuBarViewModelTests.swift         # Already covers formatting behavior
├── DisplayModeCoordinatorTests.swift   # Green
├── DisplayPreferencesStoreTests.swift  # Green
├── DisplayContentFactoryTests.swift    # Green
├── DisplayViewModelTests.swift         # Green
├── HostHealthTrackerTests.swift        # Green
├── PingSchedulerTests.swift            # Green
├── StatusPopoverViewModelTests.swift   # Green
├── ConnectionSweeperTests.swift        # Green
└── PingServiceTests.swift              # Green (network-dependent)
```

### Pattern 1: Interface Alignment Fix
**What:** Add missing parameters to test helper methods and factory initializer calls.
**When to use:** When production struct gains new required members.
**Example:**
```swift
// Source: Production ContextMenuActions now requires onOpenAbout
// Tests must include it in all ContextMenuActions.init calls

// BEFORE (stale):
ContextMenuActions(
    onSwitchHost: {},
    onToggleCompactMode: {},
    onToggleStayOnTop: {},
    onOpenSettings: {},
    onQuit: {}
)

// AFTER (aligned):
ContextMenuActions(
    onSwitchHost: {},
    onToggleCompactMode: {},
    onToggleStayOnTop: {},
    onOpenSettings: {},
    onOpenAbout: {},  // Required parameter added
    onQuit: {}
)
```

### Pattern 2: Obsolete Test Removal with Coverage Transfer
**What:** Remove tests for types that no longer exist when coverage is provided elsewhere.
**When to use:** When a test file references a type that was inlined/removed and equivalent tests exist.
**Example:**
```swift
// StatusItemTitleFormatterTests tests:
// - testCompactModeRemovesMillisecondsSuffix
// - testCompactModeLeavesFallbackTextUntouched
// - testNonCompactModeKeepsFullDisplayText

// MenuBarViewModelTests already covers:
// - formatLatencyText via testHealthyAndWarningTransitions (verifies "42 ms", "130 ms" formatting)
// - N/A fallback via testStartupStateIsGrayWithNAText and testSustainedFailureTurnsRedAfterThreshold

// Decision: Remove StatusItemTitleFormatterTests.swift as coverage exists
```

### Pattern 3: Two-Tier Verification Flow
**What:** Quick targeted validation during iteration, then full regression before completion.
**When to use:** Standard workflow for test wiring recovery phases.
**Example:**
```bash
# Tier 1: Targeted compilation check (fast)
swift build --build-tests

# Tier 1: Targeted test run for affected files
swift test --filter ContextMenuFactoryTests
swift test --filter MenuBarIntegrationSmokeTests

# Tier 2: Full regression verification (release gate)
swift test
```

### Anti-Patterns to Avoid
- **Creating stub types to satisfy stale tests:** If a test references a deleted type, don't create empty production stubs just to make tests compile. Remove or migrate the test.
- **Skipping tests permanently:** Use `--skip` only during development; all tests must run green for phase completion.
- **Merging fixes without full regression run:** Always run `swift test` (full suite) before declaring phase complete.
- **Ignoring flaky tests:** Any test requiring retry is treated as unresolved per CONTEXT.md decisions.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test filtering | Manual test file deletion/restoration | `swift test --filter` | Non-destructive, repeatable |
| Compilation checking | Running full tests to see compile errors | `swift build --build-tests` | Faster feedback loop |
| Test parallelization | Custom test runner | SPM default parallel execution | Already optimized in SPM |
| CI test integration | Custom workflow | Existing local `swift test` command | Phase 9 scope is local/CI baseline, not CI enhancement |

**Key insight:** SPM provides all necessary commands for test wiring recovery; no custom scripts or tools needed.

## Common Pitfalls

### Pitfall 1: Stale Type Reference Without Investigation
**What goes wrong:** Deleting a test file without checking if its assertions provide unique coverage.
**Why it happens:** Assuming inline-removed types have no test value.
**How to avoid:** Review test assertions and verify equivalent coverage exists elsewhere before removal.
**Warning signs:** Test file deletion without evidence of coverage transfer.

### Pitfall 2: Missing Parameter in Helper Methods
**What goes wrong:** Fixing direct initializer calls but missing helper methods that wrap those calls.
**Why it happens:** Tests often have private `makeMenu(state:)` helpers that also construct `ContextMenuActions`.
**How to avoid:** Search all test files for the type name and update ALL call sites.
**Warning signs:** First fix compiles but subsequent tests in same file fail.

### Pitfall 3: Network-Dependent Test Flakiness
**What goes wrong:** `PingServiceTests` fails intermittently due to network conditions.
**Why it happens:** Tests ping real external hosts (8.8.8.8, 1.1.1.1).
**How to avoid:** Per CONTEXT.md, single retry allowed with explicit logging; repeated flakiness blocks completion.
**Warning signs:** Tests pass locally but fail in CI, or vice versa.

### Pitfall 4: Incomplete Before/After Evidence
**What goes wrong:** Phase completion claimed without showing initial failures and final success.
**Why it happens:** Verification evidence focuses only on final state.
**How to avoid:** Capture `swift build --build-tests` failure output before fixes, then success output after.
**Warning signs:** Evidence artifact missing "before" section or compile error screenshots.

## Code Examples

Verified patterns from current project:

### Current ContextMenuActions Production Interface
```swift
// Source: Sources/PingScope/MenuBar/ContextMenuFactory.swift
struct ContextMenuActions {
    var onSwitchHost: () -> Void
    var onToggleCompactMode: () -> Void
    var onToggleStayOnTop: () -> Void
    var onOpenSettings: () -> Void
    var onOpenAbout: () -> Void      // <-- Required parameter missing in tests
    var onQuit: () -> Void
}
```

### Test Helper Pattern Requiring Fix
```swift
// Source: Tests/PingScopeTests/ContextMenuFactoryTests.swift
// Line 80-91: makeMenu helper creates ContextMenuActions without onOpenAbout

private func makeMenu(state: ContextMenuState) -> NSMenu {
    ContextMenuFactory().makeMenu(
        state: state,
        actions: .init(
            onSwitchHost: {},
            onToggleCompactMode: {},
            onToggleStayOnTop: {},
            onOpenSettings: {},
            onOpenAbout: {},  // ADD THIS
            onQuit: {}
        )
    )
}
```

### Obsolete Test Type Reference
```swift
// Source: Tests/PingScopeTests/StatusItemTitleFormatterTests.swift
// Line 5: References non-existent type

final class StatusItemTitleFormatterTests: XCTestCase {
    private let formatter = StatusItemTitleFormatter()  // TYPE DOES NOT EXIST
    // ...
}

// The formatting logic is now in:
// Source: Sources/PingScope/ViewModels/MenuBarViewModel.swift
private static func formatLatencyText(_ latencyMS: Double?) -> String {
    guard let latencyMS else {
        return "N/A"
    }
    return "\(Int(latencyMS.rounded())) ms"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate `StatusItemTitleFormatter` type | Inline `MenuBarViewModel.formatLatencyText()` | Pre-Phase 9 (production refactor) | Test file now references deleted type |
| `ContextMenuActions` without About | `ContextMenuActions` with `onOpenAbout` | Phase 6 (About menu item addition) | All test call sites need parameter |
| No standard verification command | `swift test` as canonical command | Project setup | Used for both local and CI baseline |

**Deprecated/outdated:**
- `StatusItemTitleFormatter` type - Removed, logic inlined
- `ContextMenuActions` 5-parameter initializer - Replaced with 6-parameter version

## Open Questions

Things that couldn't be fully resolved:

1. **Should StatusItemTitleFormatterTests be migrated or removed?**
   - What we know: The type no longer exists. `MenuBarViewModelTests` covers `formatLatencyText` behavior indirectly through `compactLatencyText` assertions.
   - What's unclear: Whether the compact-mode "ms" suffix stripping test provides unique value not covered elsewhere.
   - Recommendation: Remove the test file since `MenuBarViewModelTests.testHealthyAndWarningTransitions` and `testStartupStateIsGrayWithNAText` verify the formatting outputs ("42 ms", "N/A") and the status item always shows full format (no compact-specific logic remains).

2. **Are there additional stale references beyond the three identified?**
   - What we know: `swift build --build-tests` reveals exactly three call sites with signature mismatches plus one missing type.
   - What's unclear: Whether runtime-only failures exist after compilation succeeds.
   - Recommendation: Run full `swift test` after fixing compilation to discover any runtime assertion failures.

## Sources

### Primary (HIGH confidence)
- `.planning/v1.0-v1.0-MILESTONE-AUDIT.md` - Documents specific compile-blocking test wiring issues
- `Sources/PingScope/MenuBar/ContextMenuFactory.swift` - Current `ContextMenuActions` interface with 6 parameters
- `Sources/PingScope/ViewModels/MenuBarViewModel.swift` - Current formatting logic location
- `Tests/PingScopeTests/StatusItemTitleFormatterTests.swift` - Stale test file
- `Tests/PingScopeTests/ContextMenuFactoryTests.swift` - Tests requiring parameter addition
- `Tests/PingScopeTests/MenuBarIntegrationSmokeTests.swift` - Tests requiring parameter addition
- `Tests/PingScopeTests/MenuBarViewModelTests.swift` - Existing coverage for formatting behavior
- `swift build --build-tests` output - Exact compile error messages and line numbers

### Secondary (MEDIUM confidence)
- Swift Package Manager documentation - Test filtering and execution options

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SPM commands are verified against project setup
- Architecture: HIGH - Compile errors provide exact file/line references; production code inspected
- Pitfalls: HIGH - Derived from actual codebase inspection and CONTEXT.md decisions

**Research date:** 2026-02-16
**Valid until:** 2026-03-18 (30 days - test wiring is stable once fixed)
