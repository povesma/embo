# 051: Live-Edit Toggle Panel for visual-impl - PRD

**Status**: Draft
**Created**: 2026-07-28
**Author**: Claude (via dev workflow analysis)

---

## Wider Context / Higher Goal

`visual-impl` verifies design-to-code work via a conformance/pixel
check and the `visual-qa-reviewer` agent's rubric. That gates
pass/fail, but gives no fast path to tune something by taste — today
that means hand-editing (untracked, someone transcribes it back
later) or repeated rebuild/screenshot cycles. This feature closes that
gap: a live, verbal-feedback-driven session where the human only
compares renders and describes desired changes in words — any change
the agent can author (not just CSS, but markup, layout, or logic) —
and the agreed result is transcribed deterministically back into the
project's own source, the same source the deploy pipeline already
turns into what's live, not an LLM guess.

## Context

### Current State (observed)

- `visual-impl.md` and `visual-qa-reviewer.md` both currently
  self-describe as "EXPERIMENTAL" — verified via:
  `plugin/commands/visual-impl.md:1-14,350-352`,
  `plugin/agents/visual-qa-reviewer.md:1-4`, 2026-07-28.
- Maintainer correction: this is stale — the tool is mature and
  working in practice. **This PRD promotes it to stable now** (FR-11),
  not conditionally on "enough runs" as the old note said.
- The existing loop is `Parse -> Generate -> Render -> Measure ->
  Correct -> Gate`; Step 6 loops back to Step 2 on FAIL, capped at 3
  iterations — verified via: `plugin/commands/visual-impl.md:205-328`,
  2026-07-28.
- No live-edit / toggle mechanism exists anywhere in the codebase
  today — verified via: full read of both files above, no match,
  2026-07-28.
- A prototype was validated live this session against an internal POC
  branch on a staging host (identifiers redacted for confidentiality):
  toggle panel, drag, bulk on/off/invert, clipboard export, and
  navigation re-injection all worked end-to-end.

### Past Similar Features (from claude-mem)

No prior PRD matches this. Closest history: `visual-impl`'s build-out
(task 040) and the `visual-qa-reviewer` rubric — both establish
"separate judge, never self-review," which this feature does not
touch: live-edit changes what a human tunes, not who judges
conformance.

## Problem Statement

**Who**: A developer using `visual-impl` who wants to adjust something
by feel rather than by rubric — a spacing value, a markup change, a
piece of logic — or resolve a "not quite right" the automated gate
didn't flag.

**What**: No fast, source-connected way to try several candidate
changes live, compare them, and commit the chosen one back to source,
without hand-editing or a rebuild-per-attempt cycle.

**Why**: Hand-edits are untracked and don't reach source without
manual transcription — error-prone at the scale of a multi-page
redesign. Rebuild-per-attempt is slow enough to discourage trying more
than one or two alternatives.

**When**: Any `visual-impl` session — refining a build that already
passed/failed the gate, or building from scratch.

## Goals

### Primary Goal

Let a human iterate on candidate changes — of any kind the agent can
author, not limited to CSS — against a live render, using only verbal
feedback and visual comparison, and have the agreed result transcribed
deterministically back into the project's own source.

### Secondary Goals

- Keep the mechanism disposable and dependency-free — it exists only
  for the duration of a tuning session.
- Preserve the existing conformance/reviewer gate as separable and
  still available — live-edit does not replace it.
- Promote `visual-impl` from experimental to stable (FR-11).

## User Stories

### Epic

As a developer using `visual-impl`, I want to tune any candidate
change live against the running page and have my final choice
committed automatically to wherever it lives, so that I can explore
alternatives quickly without hand-editing or repeated rebuilds.

### User Stories

1. **As a** developer refining a build
   **I want** to start live-edit mode at any point in a session
   **So that** no workflow stage blocks me from tuning

   **Acceptance Criteria**:
   - [ ] `visual-impl`'s help/usage text names live-edit mode as
     available, unless suppressed by a profile setting
   - [ ] The user can request it in plain language or an explicit
     flag; no separate command/skill required
   - [ ] Available regardless of PASS/FAIL/not-yet-run state

2. **As a** developer comparing candidates
   **I want** a floating panel with one toggle per candidate change,
   generated from a fix registry
   **So that** I can turn changes on/off/in-combination instantly
   without hand-editing anything

   **Acceptance Criteria**:
   - [ ] Adding a candidate requires only one registry entry; no
     per-fix UI code, regardless of how complex the underlying change is
   - [ ] Toggling applies the change live with no reload
   - [ ] Checked rows are visually distinguished (a glance shows
     what's on)
   - [ ] Bulk controls (All ON / All OFF / Invert) exist once more than
     a couple of candidates exist
   - [ ] The panel is draggable so it doesn't obscure the page

3. **As a** developer who wants to try a new candidate mid-session
   **I want** it to become toggleable without ending the session or
   rebuilding
   **So that** exploring something the reviewer didn't originally flag
   doesn't cost a full round-trip

   **Acceptance Criteria**:
   - [ ] A new candidate (of any kind — style, markup, data, config)
     can be registered and appear as a new toggle without reloading or
     losing existing toggle state
   - [ ] The registry's initial population source is explicit: the
     reviewer's `recommended_fixes` (when live-edit follows a Gate
     result), or empty (starting from scratch)

4. **As a** developer who has settled on a combination
   **I want** to lock it in and have it written back to source
   **So that** the accepted result is traceable to my explicit choice,
   not an untracked manual edit

   **Acceptance Criteria**:
   - [ ] An export produces a plain, unambiguous ON/OFF record
   - [ ] The agent transcribes only the ON set as a mechanical,
     reproducible step — no visual re-judgment — back to the source
     locations it recorded when authoring each candidate
   - [ ] All injected scaffolding is removed after transcription;
     nothing from the session leaks into the shipped result
   - [ ] The transcribed change can be inspected before commit like
     any other change

5. **As a** developer navigating between pages mid-session
   **I want** the panel and its toggle state to reappear after a real
   navigation
   **So that** a multi-page session isn't interrupted by every link
   click

   **Acceptance Criteria**:
   - [ ] A real full-page navigation is detected and injection is
     re-applied on the new page
   - [ ] Real navigation behavior (redirects, timing, errors) is
     preserved — never intercepted or faked
   - [ ] The brief gap while the panel is absent is a stated, accepted
     limitation

## Requirements

### Functional Requirements

1. **FR-1**: Inject a floating, draggable panel into a live-rendered
   page, listing one toggle per registered candidate change.
   - **Priority**: High
   - **Rationale**: Core interaction surface.
   - **Dependencies**: Browser automation capable of live JS injection
     and DOM manipulation.

2. **FR-2**: Toggling one or more entries applies exactly the
   currently-on set live, with no reload.
   - **Priority**: High
   - **Rationale**: Instant comparison is the point.
   - **Dependencies**: FR-1.

3. **FR-3**: Bulk controls (All ON / All OFF / Invert).
   - **Priority**: Medium
   - **Rationale**: Needed once more than a few candidates exist.
   - **Dependencies**: FR-1.

4. **FR-4**: An export produces an unambiguous ON/OFF list, readable
   by both the human and the agent.
   - **Priority**: High
   - **Rationale**: The handoff point between "human decided" and
     "agent transcribes" must not be ambiguous.
   - **Dependencies**: FR-1, FR-2.

5. **FR-5**: Each registry entry carries a **source locator** (the
   file and line/selector in the project's own source) captured when
   the fix is authored — because the agent authoring the live change
   already knows which source it wrote to produce it. There is one
   target: the project's source code, the same code the deploy
   pipeline turns into what's rendering live. On lock-in, the agent
   writes only the ON set back to each entry's source locator: a
   deterministic lookup-and-write against source already known, not a
   search for "the equivalent place." No visual re-evaluation at this
   step.
   - **Priority**: High
   - **Rationale**: "Deterministic" only holds if the source location
     is known in advance, not inferred at transcription time — since
     the agent authored that source moments earlier in the same
     session, the locator is a byproduct of authoring, not a lookup
     problem to solve generically.
   - **Dependencies**: FR-4, FR-10.

6. **FR-6**: After lock-in (FR-5), all injected scaffolding is removed;
   none of it is written anywhere. An abandoned session (no lock-in)
   needs no cleanup — per NFR-2 nothing was ever persisted.
   - **Priority**: High
   - **Rationale**: The mechanism is disposable tooling, not a shipped
     artifact.
   - **Dependencies**: FR-5.

7. **FR-7**: A real full-page navigation is detected during a session,
   and the injection (panel + current registry state) is re-applied on
   the new page.
   - **Priority**: Medium
   - **Rationale**: Without this, any link click ends the session.
   - **Dependencies**: FR-1.

8. **FR-8**: `visual-impl`'s help/usage text names live-edit mode as
   available, unless suppressed by a profile setting. The mention
   appears only in static help text, never appended to a run's
   PASS/FAIL output. No dedicated menu, gate-triggered offer, or
   standalone command.
   - **Priority**: Medium
   - **Rationale**: Rejected building offer machinery around this; a
     mention tied to verdict output would behave like a gate-offer even
     if not literally triggered by one.
   - **Dependencies**: none.

9. **FR-9**: Live-edit mode is usable independent of the gate's
   outcome — before generation, after PASS, or after FAIL.
   - **Priority**: Medium
   - **Rationale**: General tuning capability, not a FAIL-recovery
     path.
   - **Dependencies**: none.

10. **FR-10**: Registry entries start from either the reviewer's
    `recommended_fixes` (live-edit follows a Gate result) or an empty
    registry populated ad hoc (starting from scratch). A new entry can
    be added at any point in a session without reload or loss of
    existing toggle state.
    - **Priority**: High
    - **Rationale**: Without this, anything not pre-registered forces
      the exact rebuild-per-attempt cycle this feature replaces.
    - **Dependencies**: FR-1.

11. **FR-11**: `visual-impl.md` and `visual-qa-reviewer.md` drop the
    "EXPERIMENTAL" label now; both are described as stable/mature.
    - **Priority**: Medium
    - **Rationale**: The label is stale; promotion is a direct part of
      this change, not a future conditional step.
    - **Dependencies**: none.

### Non-Functional Requirements

1. **NFR-1**: Usability — which entries are ON stays scannable at a
   glance regardless of registry size; never requires re-reading every
   row.
2. **NFR-2**: No persistence — none of the injected panel/state
   survives the browser session; a fresh load starts clean unless
   re-injected.
3. **NFR-3**: No new runtime dependency — vanilla JS, consistent with
   the plugin's stdlib-only constraint.

### Technical Constraints

- Integrates with the existing Playwright-CLI automation `visual-impl`
  already uses (`plugin/commands/visual-impl.md:22-27,155-191`), not
  the Playwright MCP, for the same context-budget reason documented
  there.
- Must not alter the existing conformance/reviewer gate contract —
  live-edit is additive, not a replacement path through Step 6.
- Injection is JS executed against the live page, not a checked-in
  browser extension or app code.

## Out of Scope

- A browser extension or any persisted, installable tool — disposable
  per-session tooling only; revisit if it becomes a permanent
  cross-project tool.
- The human hand-editing the target directly — the human gives verbal
  feedback and visual comparison only; the agent authors every change,
  so the accepted result stays traceable to a specific instruction.
- A dedicated menu, gate-triggered suggestion, or standalone
  command/skill for invoking live-edit mode.
- Formalizing the exact invocation syntax — left to tech-design.
- Replacing or modifying the automated conformance/reviewer gate.

## Success Metrics

1. **No manual hand-edit in a completed session**: 100% of sessions
   produce the final result via panel toggles + transcription.
2. **Transcription fidelity**: the written change after lock-in
   matches exactly the ON set's registered values (spot-checked).
3. **No scaffolding leaks**: zero occurrences of injected-panel
   markup/IDs in a committed diff after a session.

## References

### From Codebase

- `plugin/commands/visual-impl.md` — the existing loop, Gate step,
  and the status note to promote.
- `plugin/agents/visual-qa-reviewer.md` — the separate-judge contract
  this feature does not entangle with.

### From History (Claude-Mem)

- Task 040 (VISUAL-IMPL-ship-to-plugin) — establishes "separate
  judge" and conformance-over-pixel-diff, both extended, not replaced,
  by this feature.

### Prototype evidence

- Live-validated this session against an internal POC branch and
  staging host (identifiers redacted); two before/after screenshots
  exist as session evidence, confirming injection, drag, bulk toggle,
  and a mixed-state combination all worked as designed.

### Prior art (NotebookLM: "AI Visual design and Testing against
exiting figma / image design")

- **Uiprobe** — a shipping tool for property-level Figma-vs-live
  comparison (the conformance side `visual-impl.md` already lists as a
  later extension). Adjacent, not duplicated: Uiprobe verifies, this
  feature tunes.
- **Superdesign** — closest analog to the toggle → export → transcribe
  flow, but its transcription is prompt-based (the agent re-derives
  code from a description) — weaker than this PRD's deterministic,
  no-re-judgment bar (FR-5), a deliberate differentiator.
- No prior art surfaced a disposable, browser-injected toggle panel
  doing live swaps with an explicit ON/OFF export contract generalized
  beyond CSS. Research did not suggest changing the core approach.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create technical design
3. Run `/embo:tasks` to break down into tasks
