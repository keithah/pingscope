---
name: ux-test
description: >
  Run an LLM-driven UX test of PingScope's menu-bar UI and bring back evidence
  (verdict + screenshots + friction findings). Use when you want to VERIFY a
  menu-bar UX flow against the real running app — "can a first-run user set a
  target?", "is the latency graph live?", "is the refresh-interval control
  discoverable?" — instead of reasoning about the SwiftUI code alone. Trigger
  on requests like "UX test <flow>", "does <flow> actually work for a user",
  "check the popover for friction", or after changing menu-bar/popover UI.
---

# ux-test — farm out UX testing of PingScope

A second Claude agent adopts a persona, pursues a plain-language goal inside the
real running app via the `menubar-ux-tester` harness, and returns a report. You
author intent (not click scripts), trigger a run, read the evidence, fix
PingScope, and re-run. It's a loop.

Harness: `~/src/macos-testing/menubar-ux-tester`.
**Full reference (read it for scenario schema, all gotchas, and the app-side
hooks):** `~/src/macos-testing/menubar-ux-tester/docs/llm-ux-testing-skill.md`.

## Prereqs (verify once)
- `peekaboo permissions` shows Screen Recording + Accessibility granted.
- Harness installed: `cd ~/src/macos-testing/menubar-ux-tester && python3 -m venv .venv && source .venv/bin/activate && pip install -e .`
- Auth is OAuth via the Claude Code keychain token — **keep `ANTHROPIC_API_KEY` unset**.
- PingScope has the required hooks already: the status button is AX-actionable
  (`button.action = #selector(togglePopover)`) and `PINGSCOPE_UITEST` /
  `PINGSCOPE_UITEST_OPEN` render the menu-bar content in a capturable window.
  If you add a new menu-bar control, keep those patterns (see the full ref).

## The cycle

1. **Rebuild + launch in test mode** (after any source change):
   ```bash
   cd ~/src/pingscope && scripts/build-app-bundle.sh debug
   pkill -f "/PingScope\.app/Contents/MacOS/PingScope"; sleep 1
   PINGSCOPE_UITEST=1 PINGSCOPE_UITEST_OPEN=1 open ".build/arm64-apple-macosx/debug/PingScope.app"
   ```
   (`_OPEN` = launch-hook mode: content window opens at launch, no menu-bar
   interaction — the reliable path. Drop `_OPEN` to test the menu-bar open gesture.)

2. **Sanity-check capture**, then **run a scenario**:
   ```bash
   cd ~/src/macos-testing/menubar-ux-tester && source .venv/bin/activate && unset ANTHROPIC_API_KEY
   uxtest smoke Pingscope                          # exit 0 + "OK: N elements" = ready
   uxtest run scenarios/pingscope/<scenario>.yaml --model claude-opus-4-8
   ```

3. **Read the evidence** in `runs/<latest>/`:
   - `report.html` — verdict, per-step narration, friction, screenshots (open it).
   - `run.json` — machine-readable: `verdict`, `summary`, `steps[]`, `friction_events[]`.
   - `steps/step_NNN.png` — the visual evidence per step.
   ```bash
   python3 -c "import json;d=json.load(open('runs/<dir>/run.json'));print(d['verdict']);print(d['summary']);[print('•',f['tag'],'-',f['note']) for f in d['friction_events']]"
   ```

4. **Fix PingScope** based on the friction findings, rebuild (step 1), re-run the
   same scenario, confirm the verdict flips.

## Authoring a scenario
Drop a YAML in `scenarios/pingscope/`. Write persona + goal + success_criteria
(intent, not clicks). Use `open: launched`, and set `popover_root_match.label`
to visible on-screen text (e.g. `All Hosts`). Full schema + tool list
(`click`, `type_text`, `set_value`, `check_live_value`, `done`) in the reference doc.

## Gotchas (summary; full list in the ref)
- **Relaunch the app fresh before each run** — the history table bloats the AX
  tree over time until Peekaboo `see` times out. Fresh app = reliable capture.
- Always test via the UITEST window — Peekaboo can't capture a transient popover.
- Content-only flows (host health, is-the-graph-live) are reliable; Settings-
  navigation flows are rough (the "Open settings" click fails as friction and
  `see` may hang on the replaced window) — you still get findings up to that point.
- A crowded menu bar can hide the status item; launch-hook mode avoids it.
- Actions that tear down the window (e.g. "Open settings") may fail as an
  `action-failed` friction event (non-fatal now); split such flows or test the
  destination window separately.
- The content window shows app-menu/window chrome that the real popover lacks —
  ignore those elements.
