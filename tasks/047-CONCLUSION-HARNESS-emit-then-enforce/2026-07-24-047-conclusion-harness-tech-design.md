# 047: Conclusion Harness (emit-then-enforce) — Technical Design

**Status:** Draft
**PRD:** [2026-07-24-047-conclusion-harness-prd.md](2026-07-24-047-conclusion-harness-prd.md)
**Created:** 2026-07-24

## Overview

Make behavioral rules reliable by having the agent **emit its own
conclusion artifact** for whatever rule governs the current turn, then
act consistently with it. The POC proved this works **only when the
artifact's trigger is re-injected into context every prompt** — prose
alone decays and loses to already-re-injected rules.

**Honest scope statement (added after clean-context critique):** as
scoped in Layers 1–2, this system provides **no deterministic
enforcement** — it is prompting (the same category as any prose rule)
plus a re-injection aid. It does NOT meet embo's "Enforce, Don't Ask"
standard until Layer 3 (the Stop-hook consistency check) is built and
turned on. The words "harness"/"enforce" are aspirational until then.
The POC that motivated this is **author-primed and uncontrolled** (see
PRD open items) — suggestive, not proof.

**The umbrella covers ONE rule class only.** It generalizes the
single-rule result (`Objection-check` for WITHSTAND-CRITICISM) for
**user-prompt-triggered** rules — rules whose trigger is visible in the
user's message. **Model-action-triggered** rules (e.g. DATA-ACCESS,
which fires on the model's own future Bash command) CANNOT be served by
the UserPromptSubmit injection path — a prompt-time hook cannot see a
command the model has not issued yet. Those rules need the Stop-hook
transcript-scrape (Layer 3) as their **primary** mechanism, not an
optional add-on. This is a two-mechanism design, not one umbrella.

This design generalizes the single-rule result into a **two-layer
umbrella (for prompt-triggered rules)**:
1. **Umbrella mechanism (automatic, one place):** a single meta-rule
   states the emit-a-conclusion contract for *all* rules; the existing
   `behavioral-reminder.sh` auto-injects every rule's trigger line each
   prompt.
2. **Per-rule trigger line (irreducible minimum):** each enforced rule
   supplies only a one-line `CHECKLIST:` block — its trigger + decision
   axis — not the full mechanism.

Result: adding enforcement to a rule = adding one checklist line; the
mechanism is never rewritten per rule.

## Current Architecture (RLM/code-verified)

All facts below were confirmed against code on 2026-07-24, not inherited.

- **`plugin/hooks/behavioral-reminder.sh:114`** — a UserPromptSubmit
  hook extracts EVERY `CHECKLIST:` region from `commands/start.md` by
  pattern (`awk '/^\[.*checklist/ … /<!-- \/CHECKLIST -->/'`) and injects
  them **verbatim, unconditionally, every prompt** as `additionalContext`.
  This is the re-injection engine the POC relied on; it already
  auto-discovers checklists — no per-rule hook edit is needed.
  *(verified: read lines 95–121)*
- **`behavioral-reminder.sh:20–90`** — the hook ALSO has weighted
  keyword detectors (`CRITICISM`, `IMPL_REQUEST`, `GIT_REQUEST`, each
  with a threshold) driving conditional one-liner reminders (line 123).
  **These are brittle:** the `CRITICISM` detector scored **0** on the
  real POC objection "why the tech design is so big?" *(verified by
  running the detector's awk on that string, 2026-07-24)*. So the POC
  artifact fired from the **unconditional** checklist, not the detector.
- **`commands/start.md`** — the single source of truth for rule text and
  checklist blocks. Rules with reliable behavior (RESTATE-CORRECTION,
  CLEAR-OPTIONS, DELEGATE, and now WITHSTAND-CRITICISM) are exactly the
  ones with a `CHECKLIST:` block. *(verified: grep of `CHECKLIST:`)*
- **Hook visibility (from claude-code-guide, 2026-07-23):**
  UserPromptSubmit/PreToolUse hooks see the user prompt / tool input but
  NOT the agent's message text; only the `Stop` hook receives
  `last_assistant_message`. So *checking* that an artifact was emitted
  (vs merely prompting for it) can only happen at Stop.

## Past Decisions (relevant)

- **Task 039 (rule-salience):** established that injecting a rule's
  operative TEXT beats naming it — recall drops atypical clauses. The
  checklist mechanism is 039's; 047 extends it with the emit-a-conclusion
  contract. *(referenced in behavioral-reminder.sh:100)*
- **Task 046 (regex harness):** the superseded approach — external regex
  detection of violations. Disabled, kept on branch. 047 replaces its
  intent (make rules stick at action time) with model-emits-conclusion.

## Proposed Design

### Layer 1 — the umbrella meta-rule (RULE:EMIT-CONCLUSION)

One new rule in `start.md`, with its own always-injected checklist,
stating the general contract:

> For any active rule that governs THIS turn, before acting emit one
> line: `<Rule>-check: <decision from that rule's axis> — <specific
> reason>`. A bare compliance claim with no specific reason is a
> violation. If several rules govern, emit one line each.

The umbrella carries the *mechanism* (emit, be specific, one line per
governing rule). It does NOT know any rule's trigger — that is Layer 2.

### Layer 2 — per-rule trigger lines

Each enforced rule keeps a one-line `CHECKLIST:` block giving ONLY:
- **trigger** — the condition under which the rule governs a turn
  (e.g. "the user objects/challenges/questions/corrects");
- **decision axis** — the allowed values (`hold | concede | partly`).

The full "how to comply" prose stays in the rule body (read once at
session start); the checklist is the salient, re-injected trigger.
`Objection-check` (already shipped this session) is the reference
instance.

### Why unconditional injection (not detector-gated)

Enforcement MUST NOT depend on the keyword detectors. They are
deterministic and miss paraphrase (proven: 0 on the real objection); a
missed detection = a silently unenforced rule, the exact failure 047
eliminates. All trigger lines are injected every prompt; the **model**
decides which rule applies (intelligence in the model), the **hook**
guarantees the trigger line is present (determinism in the injection).
Accepted cost: per-prompt payload grows with rule count (see
Performance).

### Layer 3 (optional, later) — Stop-hook consistency check

Prompting (Layers 1–2) makes the artifact fire; it does not *prove* it
did. A `Stop` hook can read `last_assistant_message`, and — for governed
turns — verify the artifact was present and consistent with the action,
logging misses. This is the ONLY place assistant text is visible to a
hook. Measure-only first (the `conclusion-probe.sh` prototype already
does this shape); enforce (block-and-continue) only if measurement
justifies it. Out of scope for the first tasks; kept as the path.

### Data contract — a checklist block

```
<!-- CHECKLIST:<RULE-NAME>
     Injected verbatim every prompt by behavioral-reminder.sh. -->
[<RULE-NAME> checklist] <trigger>: FIRST emit `<Rule>-check: <axis>
— <specific reason>`, then act consistently. <one-line do/don't>.
<!-- /CHECKLIST -->
```
Contract with the hook: the injected line MUST start with `[` and the
block MUST end with `<!-- /CHECKLIST -->` (the awk keys on both). No hook
change is needed to add a rule — this is the genericity guarantee.

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1: umbrella meta-rule emits a conclusion for a governed rule | `manual-run-claude` | integration | JOINT evidence, not one run: Story 2 un-primed fresh-session run (governed turn emits `<Rule>-check:` unprompted) + Story 1 Stop-hook emit-rate logged across multiple real sessions. A single anecdotal run does NOT satisfy FR-1. |
| FR-2: adding a rule = one checklist block, zero hook change | `auto-test` | unit | new block is extracted by the hook's awk; `behavioral-reminder.sh` unchanged (diff-guard) |
| FR-3: all trigger lines injected unconditionally (no detector gate) | `auto-test` | unit | hook output contains every checklist regardless of prompt keywords |
| FR-4: reliability under LONG context (the open PRD caveat) | `manual-run-claude` | integration | objections late in a long session still emit the artifact |
| FR-5: (optional) Stop-hook logs artifact presence+consistency | `auto-test` | unit | synthetic Stop JSON → NDJSON row (prototype tests) |

Methods per `/embo:test-plan`.

## Umbrella-vs-per-rule decision gate (added 2026-07-24)

The umbrella (`RULE:EMIT-CONCLUSION`) is an ABSTRACTION over per-rule
checklists. It is only justified if it performs **at least as well** as
individual per-rule checklists. If measurement (Story 1) shows the
umbrella fires the correct artifact LESS reliably than per-rule
checklists — e.g. it causes the over-firing observed live (one generic
contract making the model emit ill-fitting `<Rule>-check:` lines on
non-governed turns) — then **KISS wins: keep individual per-rule
checklists and drop the umbrella.** The per-rule form is already proven
(WITHSTAND fired correctly; the umbrella has NOT been tested). The
umbrella is a maintenance-convenience bet, not a reliability bet, and
must not be adopted if it costs reliability. Story 5 (umbrella rollout)
is CONDITIONAL on this gate passing.

## Trade-offs

1. **Per-rule checklists only (no umbrella)** — proven, but duplicates
   the mechanism text per rule; the maintenance burden the user rejected.
2. **Fully generic umbrella, no per-rule lines (Recommended-against)** —
   degrades to "reason about the rules," the vague prose that was already
   violated this session. Rejected: a rule with no declared trigger forces
   the model to guess applicability — the unreliable behavior we replace.
3. **Umbrella mechanism + per-rule trigger line (CHOSEN)** — one meta-rule
   for the mechanism, one irreducible line per rule for its trigger.
   ~90% automatic; the per-rule line is the genuine minimum (only the rule
   author knows its trigger).

## Implementation Constraints

- No hook rewrite to add a rule (the auto-discovery awk already
  generalizes). Adding the umbrella meta-rule is a `start.md` edit +
  its checklist; per-rule adoption is one checklist block each.
- Every live test of a `start.md` change requires a **`plugin.json`
  version bump** — the plugin loads from a version-keyed cache, and a
  working-tree edit does not reach a running session otherwise (this bit
  the POC twice; documented in the PRD).
- `set -uo pipefail`, fail-open: a checklist that fails to extract must
  not break the hook (existing `|| true` guards hold).

## Files to Create/Modify

**Modify:**
- `plugin/commands/start.md` — add `RULE:EMIT-CONCLUSION` (umbrella) +
  its checklist; ensure each rule to be enforced has a one-line trigger
  checklist (WITHSTAND-CRITICISM done).
- `plugin/.claude-plugin/plugin.json` — version bump per live test.
- `plugin/hooks/behavioral-reminder.test.sh` (if present) or create —
  assert unconditional multi-checklist extraction (FR-2/FR-3).
- `README.md` — document the mechanism (task 7.1).
- `CLAUDE.md` — dev-only meta note; must NOT become a second home for
  behavioral rules (CLAUDE.md "not a deliverable" constraint). Scope the
  note to "this dev repo builds mechanism X"; the rule text stays in
  start.md. (task 7.2)

**Reference (already present):**
- `tasks/047-.../prototype/conclusion-probe.sh` + tests — the Layer-3
  Stop-hook measurement shape, for later.

**No change:** `behavioral-reminder.sh` — its auto-discovery already
supports arbitrary checklists; changing it would break the genericity
claim. Adding rules must require zero edits here (diff-guarded in FR-2).

## Rollback Plan

All changes are `start.md` prose + a version bump. Revert = `git checkout`
the rule file and drop the bump; no state, no migration. The 046 harness
is already disabled independently.

## Open items (from the clean-context critique, 2026-07-24)

- **Priming confound (critical, gates everything).** The POC was
  author-primed and same-session. The core causal claim ("re-injection,
  not prose, fires the artifact") is unproven until a fresh un-primed
  session tests it. **Measurement (Layer 3) must precede umbrella
  rollout** — do NOT write `RULE:EMIT-CONCLUSION` into the shared
  start.md and adopt more rules before the existing WITHSTAND checklist
  is measured across fresh sessions.
- **Payload-growth salience.** Unconditional injection makes the
  re-injected block LARGER as rules are added — risking the same
  salience-decay-to-volume failure this mechanism fixes, moved up one
  level. No N-budget is set. Needs a size bound / experiment before mass
  adoption. (tech-design "accepted cost" was too glib.)
- **Over-firing (observed live).** The always-present `Objection-check`
  was applied to a habit-correction turn it does not govern. Trigger
  lines must be discriminating; the umbrella needs artifact *selection*
  (which rule governs), not just emission.
- **Action-triggered rules** (DATA-ACCESS class) are NOT covered by
  Layers 1–2; they need Layer 3 as primary. Any "covers all rules" claim
  is scoped to prompt-triggered rules only.
- **Long-context durability** (FR-4) remains open as before.

**Sequencing correction:** Layer 3 (measurement) moves BEFORE the
umbrella rollout in the task order. The tasks doc is re-sequenced
accordingly.

## References

- `plugin/hooks/behavioral-reminder.sh:20-125` — detectors + injection.
- `plugin/commands/start.md` — rule + checklist source of truth.
- PRD §POC outcome — the 3-run POC result (author-primed, uncontrolled;
  see PRD open items) and the re-injection hypothesis.
- NotebookLM notebook `f7d92dcc-7e99-4a7a-b5c1-d7d379838766` — evidence.
