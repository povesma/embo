# 055: Subagent Rule Inheritance — PRD

**Status**: Draft
**Created**: 2026-09-02
**Task**: 055-SUBAGENT-RULE-INHERITANCE-unattended-agents
**Author**: Claude (via /embo:prd hybrid analysis)

---

## Wider Context / Higher Goal

Make embo's delegated subagents **run unattended** — without stopping for
approvals or bouncing decisions back to the human — **so agentic
development conserves the developer's attention instead of fragmenting
it**. Task 044 decided *when* to delegate; a spawned subagent then stalls
because it never receives the rules the main agent runs under. Every stall
pulls the human back in and defeats delegation. This feature makes a
subagent behave like the agent that spawned it, via a deterministic
mechanism (embo's "Enforce, Don't Ask" principle) rather than hoping each
agent definition remembers the rules.

## Context

The user observed that spawned subagents stop for approvals and ask
decisions they should resolve themselves, because they lack the main
agent's rules (DECIDE-OR-ASK, AVOID-APPROVAL, CLEAR-OPTIONS).

### Current State (observed)

**Root cause chain** (each link verified 2026-09-02):

- A `UserPromptSubmit` hook (`behavioral-reminder.sh`) injects the rule
  checklists into the **main** agent by extracting `<!-- CHECKLIST -->`
  regions from `start.md` — verified via `plugin/hooks/behavioral-reminder.sh:110-121`,
  `plugin/hooks/hooks.json:14-27`.
- A subagent's system prompt is **only its `.md` body**, not the Claude
  Code system prompt — verified via sub-agents docs.
- Subagents inherit CLAUDE.md, but embo forbids putting workflow rules
  there — the rules live in command files — verified via `CLAUDE.md` +
  `grep RULE:DECIDE-OR-ASK plugin/` (command files only).
- So shipped agent bodies carry **no** behavioral rules — verified via
  `plugin/agents/examine-advisor.md:1-60`.
- A subagent has no user prompt, so `behavioral-reminder.sh` never fires
  for it and the rules never arrive — [assumption, verify in tech-design;
  docs confirm `UserPromptSubmit` is a user-turn event but do not
  enumerate subagent firing].

**What already works and what's missing**:

- `PreToolUse`/`PostToolUse` fire inside subagents (with
  `agent_id`/`agent_type`) — verified via hooks docs. So embo's
  `approve-compound.sh` auto-approval already reaches subagent Bash. The
  missing half is the **judgment** rules, not command reshaping.
- `SubagentStart` exists and **supports
  `hookSpecificOutput.additionalContext`** — it can inject rules into a
  subagent exactly as `UserPromptSubmit` does for the main agent —
  verified via hooks docs + web search of the hooks reference. The
  subagent's task prompt is **not** reliably available there yet (open
  feature request), so injection must be **static/universal** — acceptable,
  since the rules are universal.
- `permissionMode` frontmatter (`acceptEdits`/`dontAsk`/`bypassPermissions`/…)
  controls harness prompting; a parent running `bypassPermissions`/
  `acceptEdits` overrides it. No agent message can grant a permission —
  safety must come from harness settings + injected rules, never from a
  subagent talking past a prompt — verified via sub-agents docs.

### Past Similar Features (claude-mem)

- **044 (delegation, obs #30645)** — decides *to* delegate; 055 makes the
  delegate *behave*. Complementary, not overlapping.
- **047 / #28979 / #35679** — the `CHECKLIST`-extraction pattern 055
  retargets from `UserPromptSubmit` to `SubagentStart`.

## Problem Statement

**Who**: a developer who delegates work to subagents.
**What**: subagents stall on approvals and ask resolvable questions,
lacking the main agent's rules.
**Why**: each stall re-engages the human (negating delegation's time
saving) and lowers quality (no DECIDE-OR-ASK → either a needless menu or a
blind guess; no CLEAR-OPTIONS when a choice does surface).
**When**: every delegated subagent run — research, analysis, and ad-hoc
`general-purpose`/`Task` spawns.

## Goals

**Primary**: every spawned subagent runs under the **same rules as the
main agent**, delivered by a **central deterministic mechanism**, so
delegated work completes unattended at the main agent's safety level and
decision quality.

**Secondary**: cover future/ad-hoc spawns (not just the five shipped
agents); keep the subagent ceiling **identical to the main agent's**;
reuse the single source of truth for rule text (no per-agent duplication).

## User Stories

### Epic

As an embo user, I want spawned subagents to run under the main agent's
rules, so delegated work completes unattended, safely, and at high quality.

1. **As a** user delegating a task, **I want** the subagent to receive
   DECIDE-OR-ASK / AVOID-APPROVAL / CLEAR-OPTIONS automatically, **so that**
   it decides recoverable choices instead of stalling on a question it
   cannot even surface.
   - [ ] On spawn, the subagent's context contains the same rule checklists
     the main agent receives, verbatim from the single source of truth.
   - [ ] Delivered with **no** edit to the subagent's `.md` (central
     mechanism).
   - [ ] A transcript shows the subagent applying DECIDE-OR-ASK (deciding
     with a one-line reason), not returning a bare question.

2. **As a** user, **I want** the harness not to prompt me for a subagent's
   recoverable actions, **so that** it runs to completion on its own.
   - [ ] Recoverable actions (read, edit, tests, feature-branch
     commit/push) proceed without a prompt.
   - [ ] These named irreversible/shared-state actions still stop:
     force-push, merge to a shared base, branch/data delete, external
     messages — the harness ceiling does not exceed the main agent's.
   - [ ] The setting is calibrated (`acceptEdits`), **not**
     `bypassPermissions`.

3. **As a** user spawning an ad-hoc `general-purpose` subagent, **I want**
   it to inherit the same rules, **so that** the fix isn't limited to the
   five committed definitions.
   - [ ] Ad-hoc/`Task` spawns receive the rules through the same central
     mechanism, no manual step required.

4. **As a** maintainer, **I want** subagent rules to come from the same
   source as the main agent's, **so that** one edit updates both.
   - [ ] Rule text is extracted at runtime from the existing checklist
     regions; changing one region changes what subagents receive, with no
     second edit.

5. **As a** user, **I want** graceful degradation, **so that** a subagent
   still runs if the mechanism is unavailable.
   - [ ] Hook errors fail open (subagent runs); absence never blocks a
     spawn.

## Requirements

### Functional

1. **FR-1**: A `SubagentStart` hook injects a **filtered subset** of the
   main agent's rule checklists into every spawned subagent via
   `hookSpecificOutput.additionalContext`, extracted at runtime from the
   existing single source of truth. *(High)*
   - **Include**: DECIDE-OR-ASK (resolve recoverable choices; do not
     stall), AVOID-APPROVAL + the relevant CAPTURE-OUTPUT context (keep
     command shapes auto-approvable), WITHSTAND-CRITICISM (hold position
     under pushback from the parent or another agent), RESEARCH-VERIFY
     (check docs/Context7 before asserting).
   - **Exclude**: CLEAR-OPTIONS and RESTATE-CORRECTION. A subagent has **no
     interactive channel to the human**, so CLEAR-OPTIONS' `AskUserQuestion`
     mandate would make it *stall* — the exact failure this feature
     removes. RESTATE-CORRECTION's `[correction]` marker has no capture
     target in a subagent turn and only adds noise. The exclusion, with
     this rationale, is a first-class requirement, not an implementation
     detail.
2. **FR-2**: Subagents run under a calibrated `permissionMode`
   (`acceptEdits`) that auto-allows recoverable actions and leaves
   irreversible/shared-state ones gated by harness prompting — a
   harness-level ceiling that **does not exceed** the main agent's.
   Judgment-level gating of irreversible actions is supplied by the
   injected DECIDE-OR-ASK (FR-1). *(High)*
3. **FR-3**: FR-1/FR-2 cover the five shipped agents (`rlm-subcall`,
   `session-scout`, `examine-advisor`, `approach-validator`,
   `visual-qa-reviewer`). *(High)*
4. **FR-4**: The same central mechanism covers ad-hoc/`general-purpose`
   spawns, plus a documented dispatch-prompt convention as a fallback for
   cases the hook cannot reach. *(High)*
5. **FR-5**: No rule prose is duplicated into agent bodies or a new file —
   single source of truth. *(High)*
6. **FR-6**: Any mechanism error fails open; the subagent runs normally.
   *(High)*

### Non-Functional

- **NFR-1 (Performance)**: negligible startup latency (~`behavioral-reminder.sh`
  class); footprint grows only by the rule block.
- **NFR-2 (Safety)**: the subagent's **harness-level ceiling does not
  exceed** the main agent's, and irreversible/shared-state actions stay
  gated by harness prompting (force-push, merge to shared base, delete
  data/branches, external messages). `bypassPermissions` is not used. This
  is not "equal" to the main agent in the human-in-the-loop sense — a
  subagent runs many actions with no user turn between them; injected
  DECIDE-OR-ASK is the judgment-level compensation, not a proof of
  equality.
- **NFR-3 (Maintainability)**: one rule edit updates main + subagent
  behavior.
- **NFR-4 (Observability)**: a subagent transcript can confirm the rules
  arrived and were applied (the `Decide-check:`/`Shape-check:` artifacts
  appear).

### Technical Constraints

- **Integrate with**: existing hooks (`hooks.json`, the
  `behavioral-reminder.sh` extraction, `approve-compound.sh`).
- **Follow**: runtime `CHECKLIST` extraction; fail-open `trap 'exit 0'`;
  auto-approvable command shapes.
- **Cannot**: move rules into CLAUDE.md; rely on any agent message to grant
  permission.
- **Bounded by**: static (universal) injection only — the subagent task
  prompt isn't reliably available at `SubagentStart`.

## Out of Scope

- Task-tailored injection keyed on the subagent's prompt (blocked upstream).
- Moving rules into CLAUDE.md.
- Authoring new rules or changing existing rule content (this delivers
  existing rules to a new audience).
- Full autonomy for irreversible actions (explicitly rejected).
- The `test-*` subagents that ship separately (task 033) — covered by the
  mechanism if present, not authored here.

## Success Metrics

1. A delegated task that previously stalled completes with **0** human
   interventions for recoverable actions.
2. A spawned subagent emits a `Decide-check:` or `Shape-check:` artifact
   for at least one qualifying action in its transcript (observable proxy
   that the rules arrived and were applied; a test-only canary agent may
   additionally confirm the injection string was present in its own
   context).
3. **0** irreversible/shared-state subagent actions without a gate.
4. One checklist edit changes both main + subagent behavior (verified by
   test).

## References

- **Codebase**: `plugin/hooks/behavioral-reminder.sh` (pattern to
  retarget), `plugin/hooks/hooks.json`, `plugin/hooks/approve-compound.sh`,
  `plugin/commands/start.md` (single source of truth),
  `plugin/agents/*.md` (rule-free today).
- **History**: 044 (complement), 047/#28979/#35679 (extraction pattern),
  027/029 (compound-approval hook already reaching subagents).
- **Docs (verified 2026-09-02)**:
  [sub-agents](https://code.claude.com/docs/en/sub-agents),
  [hooks](https://code.claude.com/docs/en/hooks),
  [SubagentStart task-prompt request #87411](https://github.com/anthropics/claude-code/issues/87411).

---

**Assumptions to close in tech-design**:

*Blocking pre-conditions — a ~2-minute live probe must run BEFORE design
work; a wrong answer changes or cancels the direction:*
1. **Root cause**: confirm `UserPromptSubmit` does NOT fire in subagents.
   If it does, the rules already arrive and this feature may be
   unnecessary or would double-inject — the whole premise changes. Probe:
   spawn a subagent with a log line in `behavioral-reminder.sh` and check
   whether it fires.
2. **Injection works**: confirm `SubagentStart` `hookSpecificOutput.additionalContext`
   actually reaches the subagent in the installed Claude Code version.
   Probe: inject a canary string, check it appears in the subagent
   transcript.
3. **Salience/position**: confirm the injected context lands where the
   subagent reads it reliably — not buried after a long `.md` body
   (lost-in-the-middle risk). Probe: same canary run — check the subagent
   *references* the canary, not just that it was present. If salience is
   low, the hook must structure the injection as a salient directive
   (bold header), the way task 047's verbatim-checklist pattern does.

*Non-blocking — settle during design:*
4. Choose the exact permission calibration that does not exceed the main
   agent's ceiling, and confirm parent-mode precedence
   (`bypassPermissions`/`acceptEdits`) doesn't silently over/under-ride it.
5. Define the FR-4 dispatch-prompt fallback convention (a standard
   `[RULES: ...]` header copied from the hook output) or defer it to a
   named follow-on task.

**Next**: `/embo:tech-design` → `/embo:tasks`.
