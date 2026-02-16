---
phase: 09-regression-test-wiring-recovery
verified: 2026-02-16T20:28:13Z
status: passed
score: 3/3 must-haves verified
---

# Phase 9: Regression Test Wiring Recovery Verification Report

**Phase Goal:** Restore cross-phase test wiring so automated regression checks compile and run cleanly.
**Verified:** 2026-02-16T20:28:13Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Test targets compile without stale symbol/signature errors | ✓ VERIFIED | `swift build --build-tests` completed with exit 0 and no compile errors. |
| 2 | `StatusItemTitleFormatter` and `ContextMenuActions` test wiring aligns with current production interfaces | ✓ VERIFIED | `StatusItemTitleFormatterTests.swift` is absent (obsolete test removed), no `StatusItemTitleFormatter` matches under `Tests/PingScopeTests`, and both test files include `onOpenAbout` matching production `ContextMenuActions` in `Sources/PingScope/MenuBar/ContextMenuFactory.swift:10-16`. |
| 3 | Regression suite can run to completion in CI/local verification flow | ✓ VERIFIED | `swift test` completed successfully: 60 tests executed, 0 failures, full suite finished. |

**Score:** 3/3 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `Tests/PingScopeTests/ContextMenuFactoryTests.swift` | ContextMenuFactory tests with current `ContextMenuActions` signature | ✓ VERIFIED | Exists (117 lines), substantive XCTest coverage, wired to production via `ContextMenuFactory().makeMenu(...)` and `ContextMenuItemID.about`; includes `onOpenAbout` in both action setups. |
| `Tests/PingScopeTests/MenuBarIntegrationSmokeTests.swift` | Integration smoke tests with current `ContextMenuActions` signature | ✓ VERIFIED | Exists (136 lines), substantive integration checks, wired to production via `ContextMenuFactory().makeMenu(...)`; includes `onOpenAbout` in initializer. |
| `Tests/PingScopeTests/StatusItemTitleFormatterTests.swift` | Obsolete stale-symbol test removed | ✓ VERIFIED | File is missing by design (expected deletion), and no `StatusItemTitleFormatter` symbol usage remains in test sources. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `Tests/PingScopeTests/ContextMenuFactoryTests.swift` | `Sources/PingScope/MenuBar/ContextMenuFactory.swift` | `ContextMenuActions` initializer signature match | ✓ VERIFIED | Test includes `onOpenAbout` and `onQuit` closures in initializer; production struct requires both. |
| `Tests/PingScopeTests/MenuBarIntegrationSmokeTests.swift` | `Sources/PingScope/MenuBar/ContextMenuFactory.swift` | `ContextMenuActions` initializer signature match | ✓ VERIFIED | Integration test initializer includes `onOpenAbout` in same slot/order required by production interface. |
| Test targets | SwiftPM test runner | local verification flow (`swift build --build-tests`, `swift test`) | ✓ VERIFIED | Build and full regression execution both complete without stale wiring failures. |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
| --- | --- | --- |
| Phase 9-specific entries in `.planning/REQUIREMENTS.md` | N/A | No explicit Phase 9 mapping found to verify. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `Tests/PingScopeTests/ContextMenuFactoryTests.swift` | - | None detected (`TODO/FIXME/placeholder/empty impl/console.log`) | Info | No blocker/warning anti-patterns detected. |
| `Tests/PingScopeTests/MenuBarIntegrationSmokeTests.swift` | - | None detected (`TODO/FIXME/placeholder/empty impl/console.log`) | Info | No blocker/warning anti-patterns detected. |
| `Tests/PingScopeTests/PingServiceTests.swift` | - | None detected (`TODO/FIXME/placeholder/empty impl/console.log`) | Info | No blocker/warning anti-patterns detected. |

### Human Verification Required

None. Automated structural and execution checks for this phase goal are sufficient.

### Gaps Summary

No gaps found. Must-haves are present, substantive, wired, and validated by successful compile and full regression test execution.

---

_Verified: 2026-02-16T20:28:13Z_
_Verifier: Claude (gsd-verifier)_
