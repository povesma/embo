# 044: Subagent Utilization — Technical Design

**Status**: Draft
**PRD**: [2026-07-21-044-subagent-utilization-prd.md](./2026-07-21-044-subagent-utilization-prd.md)
**Created**: 2026-07-21

## Overview

Four deliverables: a delegation session rule (FR-1), suggestion
checkpoints in six command files (FR-3), free-form trigger sentences
in the four agent descriptions (FR-4), and a post-delegation
verification clause (FR-5). No new binaries, no hooks, no state
files. All changes are prose in command/agent markdown plus rule
text loaded by the existing `behavioral-reminder.sh`.

**FR-2 (a tool-call-counting hook) was cut** after a live spike and a
design review — see "Rejected: the reactive nudge hook" below. The
mechanism that remains is deliberately the one that fires *at the
decision point, before exploration happens* (the rule and the
checkpoints), not one that reacts after reads are already paid for.

## Current Architecture (RLM-verified)

All claims re-verified this session (2026-07-21):

- Hook registration: `SessionStart`, `UserPromptSubmit` (context-guard,
  behavioral-reminder), `PreToolUse` matcher `Bash` (approve-compound)
  — `plugin/hooks/hooks.json:4-38`
- Transcript-reading precedent: `context-guard.sh:32-47` takes
  `transcript_path` from stdin JSON, size-guards (`:38-39`), reverse-
  greps the last assistant line — the stateless pattern FR-2 reuses
- Context injection: `behavioral-reminder.sh:139-144` emits
  `hookSpecificOutput.additionalContext` on UserPromptSubmit;
  checklist extraction from `start.md` at `:110-115`
- Existing spawn points and agent descriptions: as stated in PRD
  Current State, re-verified by the feasibility critique pass this
  session (grep + frontmatter reads)

Hook API facts (docs research via claude-code-guide agent,
code.claude.com/docs/en/hooks.md, 2026-07-21):

- Hook stdin includes `session_id`, `transcript_path`, `cwd`, and
  `agent_id`/`agent_type` when firing in a subagent context —
  **subagent detection is a field check, not a heuristic**
- PreToolUse output supports `permissionDecision: allow|deny|ask` and
  an `additionalContext` field; **whether the model sees
  `additionalContext` alongside `allow` is NOT DOCUMENTED → SPIKE-1**
- PostToolUse output has no `additionalContext` → rejected as a
  nudge channel
- Matchers support regex alternation (`"Edit|Write"` documented)
- Transcript is JSONL; exact per-line schema undocumented →
  verified from a real transcript sample during implementation
  (SPIKE-2, folded into the hook's fixture test)

## Proposed Design

### Component 1: RULE:DELEGATE session rule (FR-1, FR-5)

New RULE block + CHECKLIST block in `plugin/commands/start.md`,
same format as the existing 11 rules. Content (normative source is
the PRD's Decision Framework):

- 6 spawn triggers, 6 counter-triggers (incl. cost proportionality)
- Declare-before-explore restatement (FR-2, Component 2): the
  one-line `Delegation: …` statement required before bulk work
- Suggestion protocol: AskUserQuestion only; question text carries
  the marker `[delegate:trigger-<n>]`; decline suppresses that
  trigger for the session
- Handoff checklist: task + boundaries, in-scope paths, constraints,
  expected output shape, explicit must-NOTs
- Verification clause (FR-5): after a delegated run claiming side
  effects, re-read changed files / `git diff` / re-run the claimed
  check before reporting success
- CHECKLIST block kept ≤ ~60 tokens (a pointer-style summary, not
  the full framework — the RULE block is loaded once at session
  start; per-turn injection only needs the reflex reminder). The
  checklist's one imperative is the declare-before-explore line,
  since that is the failure mode salience must guard.

### Component 2: Declare-before-explore restatement (FR-2)

The mechanism for catching a delegation moment *before* the cost is
paid is a required spoken restatement, modeled directly on
RULE:RESTATE-CORRECTION. It is prose in the RULE:DELEGATE block plus
a CHECKLIST:DELEGATE block, both in `start.md`, the latter injected
every turn by `behavioral-reminder.sh`.

**The rule**: before beginning a bulk exploration (a search or
multi-file read that will span several files), state one line —
`Delegation: <delegating to X | not delegating, because
<counter-trigger>>` — *then* proceed. The statement comes before the
reads, so when the decision is "delegate," the reads never enter the
main context in the first place.

Why this is the right mechanism and a hook is not (see rejected
options): the intent to explore broadly exists only in the model,
before the first tool call. No external script can observe it
without guessing. The model declaring it out loud is the only
signal that is both accurate and pre-read. And, exactly as with
RESTATE-CORRECTION, the spoken line is a claude-mem-visible trace:
`/embo:improve` can later surface turns where broad reading happened
with no delegation line, or where the stated reason was wrong — the
"should have delegated" correction the PRD's Success Metric 2 needs.

**What it deliberately does not do**: no counting, no threshold, no
tool interception. The judgment (is this bulk? does a counter-trigger
apply?) is the model's, made visible, not a number computed by a
script.

#### Rejected: the reactive nudge hook

A `PreToolUse` hook (matcher `Read|Grep|Glob`) that counted
Read/Grep/Glob calls since the last user prompt and injected a
reminder via `additionalContext` once the count crossed a threshold.
A live spike (SPIKE-1) confirmed the injection channel works —
`permissionDecision: "allow"` + `additionalContext` reaches the model
mid-turn without blocking the call — and a full implementation passed
14 fixture tests. It was still cut, because:

- **It fires after the cost is paid.** By the time the count reaches
  the threshold, those N files are already in the main context. The
  benefit of delegation (keeping the bulk out) is gone; spawning an
  agent for file N+1 onward salvages little and helps nothing for the
  common short burst. The mechanism structurally cannot fire before
  the reads it counts.
- **A hook cannot see intent.** It receives one tool call at a time
  with no plan; the only pre-read signal it could key on is
  keyword-scanning the model's prose, which is guessing and was
  explicitly ruled out.
- Variant B (a retrospective `UserPromptSubmit` count reported next
  turn) was rejected with it — same after-the-fact defect, one turn
  later still.

The spike artifacts (`delegation-nudge.sh`, its tests and fixtures,
the `hooks.json` registration) were built and then removed; the
spike proved a reusable fact — PreToolUse `additionalContext` is
model-visible under `allow` — recorded here for any future feature
that needs a genuinely pre-action hook signal.

### Component 3: Command checkpoints (FR-3)

Each checkpoint is a **one-line pointer** to RULE:DELEGATE — it names
only what is command-specific (which trigger, at which point, the
marker), never restating the mechanics (marker meaning,
counter-triggers, protocol, handoff, verify), which live once in
RULE:DELEGATE in `start.md`. This avoids the same rule text drifting
across seven files.

| File | Checkpoint | Trigger |
|------|-----------|---------|
| `prd.md`, `tech-design.md`, `tasks.md` | before the approval gate: offer clean-context critique of the drafted doc | 2 |
| `impl.md` | before bulk pattern discovery; when a story contains ≥3 independent subtasks | 1, 4 |
| `health.md`, `check.md` | when a diagnosis requires iterative probing | 5 |
| `git.md` | deploy/verify loops in delivery flows | 5 |

`impl.md` note: existing prescribed profile-test-agent spawns are
untouched; the checkpoint text states it covers only moments not
already prescribed.

### Component 4: Agent description extensions (FR-4)

Append one sentence to each of the 4 agent frontmatter descriptions
naming its free-form trigger, e.g. approach-validator: "Also useful
outside /embo:research:verify whenever a chosen approach needs
independent proof before implementation." No other frontmatter
changes; prescribed command spawns unaffected (they invoke by name).

### Data Contracts

- **Declaration line**: `Delegation: <delegating to <agent> |
  not delegating, because <counter-trigger>>` — emitted in the
  model's response before bulk exploration. Greppable prefix
  `Delegation:` for claude-mem/`/embo:improve` retrieval.
- **Suggestion marker**: `[delegate:trigger-<n>]`, n ∈ 1..6, inside
  AskUserQuestion question text (written by the model per
  RULE:DELEGATE, checked by review not runtime)
- No machine-parsed contract: every artifact here is prose the
  model emits and a human or `/embo:improve` reads. There is no
  hook input/output schema in this design.

## Trade-offs

1. **Reactive counting hook (PreToolUse or UserPromptSubmit)** —
   built, spiked, tested, then rejected: fires after the reads it
   counts are already in context, and cannot see intent without
   guessing. Full reasoning under Component 2 → "Rejected".
2. **Declaration line vs silent model judgment** — chosen the
   spoken line: silent judgment leaves no trace for `/embo:improve`
   and is the exact "model forgets under load" failure the repo's
   Enforce-Don't-Ask principle warns against; the visible line is
   the enforcement.
3. **Declaration for every read vs only bulk exploration** — scoped
   to bulk only: a `Delegation:` line before every single Read would
   be intolerable noise and violate NFR-3. The line is required only
   when the model is about to begin multi-file exploration.

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1 rule + checklist in start.md | `manual-run-claude` | integration | new session banner shows DELEGATE tag; checklist injected |
| FR-2 declaration line | `manual-run-claude` | integration | a session that begins bulk exploration emits a `Delegation:` line before the reads |
| FR-3 checkpoints | `manual-run-claude` | integration | doc command run reaches approval gate with critique offer |
| FR-4 descriptions | `code-only` | — | — |
| FR-5 verification clause | `observation` | — | delegated-edit session shows parent re-checking diff |

All FR-2 evidence is behavioral (observed in a live session and in
claude-mem), not a unit test — the mechanism is a rule, not code.

## Files to Create/Modify

**Create**: none (no new files).

**Modify**:
- `plugin/commands/start.md` — RULE:DELEGATE + CHECKLIST blocks
  (incl. the declare-before-explore restatement)
- `plugin/hooks/behavioral-reminder.sh` — add DELEGATE to the
  BASELINE rules banner (the CHECKLIST is picked up automatically by
  the existing extraction)
- `plugin/commands/{prd,tech-design,tasks,impl,health,check,git}.md`
  — one-line checkpoint pointers
- `plugin/agents/{rlm-subcall,examine-advisor,approach-validator,visual-qa-reviewer}.md`
  — description trigger sentences

## Security & Performance

- No code, no hook, no I/O added. The only runtime cost is the
  per-turn CHECKLIST:DELEGATE injection, capped at ≤60 tokens by the
  same budget as the existing checklists.

## Rollback Plan

Revert the prose blocks in `start.md`, the seven commands, and the
four agent files. No data, state, or registration to migrate — the
change is entirely markdown.

## References

- Code: `plugin/hooks/context-guard.sh` (transcript pattern),
  `behavioral-reminder.sh` (additionalContext + checklist
  extraction), `approve-compound.sh` (PreToolUse conventions),
  `corrections-lib.test.sh` (test conventions)
- History: task 039 story 6.0 (deferred AskUserQuestion matcher),
  task 015 (AWSK reminder design), task 027/030 (PreToolUse
  approve/capture hook)
- Docs: code.claude.com/docs/en/hooks.md (input fields, output
  fields, matchers — fetched 2026-07-21)

---

**Next Steps**: review → `/embo:tasks`
