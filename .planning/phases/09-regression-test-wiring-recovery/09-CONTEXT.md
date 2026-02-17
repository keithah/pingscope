# Phase 9: Regression Test Wiring Recovery - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Restore cross-phase automated regression wiring so test targets compile and run cleanly. The work in this phase is limited to repairing stale test references/signatures and re-establishing a compile-green regression baseline for local and CI verification flow.

</domain>

<decisions>
## Implementation Decisions

### Regression baseline scope
- Treat this as a regression wiring recovery phase, not a net-new test feature phase.
- Completion requires compile-green test targets and runnable regression checks for the areas affected by stale wiring (`StatusItemTitleFormatter` and `ContextMenuActions`) plus their integration path.
- Prefer running the full regression suite for final sign-off when feasible; if runtime constraints prevent full execution in a single pass, run a documented staged flow that still reaches full coverage before completion.

### Failure policy during runs
- Use strict failure semantics for deterministic failures: compile errors, symbol/signature mismatches, and reproducible assertion failures must block completion.
- Allow limited automatic retry only for clearly transient/flaky failures (single retry), and only with explicit logging that identifies the retry reason and result.
- Do not mask instability: any test that requires repeated retries or remains flaky after one retry is treated as unresolved and blocks completion.

### Verification run flow
- Define one canonical verification sequence for local and CI so downstream agents converge on the same pass/fail contract.
- Keep a two-tier execution experience: quick targeted validation while iterating, then full regression verification as release gate for this phase.
- Keep command entry points simple and repeatable so future agents can execute without interpretation.

### Evidence and sign-off
- Produce explicit before/after evidence in phase artifacts: what was stale, what was changed, and the command results showing compile-green and run completion.
- Include concrete command invocations and outcomes (success/failure) for both targeted and full verification paths.
- Phase is accepted only when evidence shows the regression suite can complete in the normal local/CI flow without stale wiring errors.

### Claude's Discretion
- Exact naming of helper scripts/targets used to express quick vs full verification modes.
- Ordering of intermediate fix commits, as long as each task remains atomic and traceable.
- Formatting style of verification logs/artifacts, provided results are clear and auditable.

</decisions>

<specifics>
## Specific Ideas

No specific requirements - open to standard approaches that maximize reliability and auditability.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---

*Phase: 09-regression-test-wiring-recovery*
*Context gathered: 2026-02-16*
