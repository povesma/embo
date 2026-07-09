# 039: Rule Salience — Make Always-On Behavioral Rules Fire at Point of Action

Combined doc (problem + root cause + design + tasks). Compact by
agreement: the analysis was done live in the 2026-07-09 session with
three documented failure examples; a separate PRD/tech-design would
restate this file.

## Problem

The always-on behavioral rules loaded by `/embo:start` — most visibly
CLEAR-OPTIONS and DECIDE-OR-ASK — are violated in most turns unless the
user manually re-invokes them. Three live examples (2026-07-09 session,
plus two from another project on the same embo version) show the same
two failures:

1. **Point-of-action failure**: the turn-closing menu omits the
   choice-kind (exclusive / combinable / ordering) and the recommended
   marker, or buries options in prose.
2. **Misremembering failure**: when the user names the violated rule,
   Claude reconstructs the rule from memory instead of re-reading it,
   and the reconstruction is wrong in a systematic way — it keeps the
   parts matching the trained default ("one option per line, with
   descriptions") and drops exactly the atypical clauses (declare the
   kind, mark the recommendation).

Meanwhile the process rules inside command files (`/start` steps,
`/impl` ONE-SUBTASK, etc.) are followed reliably.

## Root cause

Presence in context is not consultation. The rules stay in the context
window all session (no compaction), but generation attends to spans the
current step points at. The difference between rules that hold and
rules that fail:

| Property | Command process rules (hold) | Active rules (fail) |
|---|---|---|
| Shape | Content: output is built FROM the text; no other source exists | Manner: output producible entirely from trained defaults |
| Competing default | None (model cannot invent `/start` step 2) | Strong (natural prose "What next? - a - b" ending) |
| Position | Injected fresh at invocation; `/impl` re-reads per subtask | Injected once at session turn 1 |
| Reminder channel | n/a | Banner lists NAMES only for the failing rules; the 3 rules the banner re-injects WITH content (criticism/impl/git triggers) hold |

Misremembering follows from the same mechanism: a rule NAME triggers
gist reconstruction (regression to the prototype), not a re-read of the
distant verbatim text.

Rejected designs, with reasons (user decisions, 2026-07-09):

- **Stop-hook block-and-redo** (force turn regeneration when the
  closing menu is malformed): redo costs more tokens than it saves,
  false positives on a prose detector trap legitimate turns, loop
  risk. Rejected.
- **Hardcoding rule text into the hook**: a second source of truth
  that drifts from `start.md`. Rejected.
- **Name-only banner reminders**: proven ineffective — that was the
  failing state this task fixes.

## Design (accepted)

1. **CLEAR-OPTIONS rewritten AskUserQuestion-first**
   (`plugin/commands/start.md`): every choice offered to the user —
   including the closing "what next?" — goes through `AskUserQuestion`
   (kind stated in the question text, `multiSelect` from the kind,
   every option with a concise description, "(Recommended)" first only
   when genuine). Text `a) option — description` form is a fallback for
   >4 options only. Consequence framing added (a malformed choice makes
   the user decide on a false picture — that loses work).

2. **Banner carries the verbatim checklist, extracted at runtime**
   (`plugin/hooks/behavioral-reminder.sh`): the rule file contains a
   compact block between `<!-- CHECKLIST:CLEAR-OPTIONS -->` and
   `<!-- /CHECKLIST -->`; the hook extracts it with awk on every
   UserPromptSubmit and appends it to the baseline banner. Single
   source of truth: editing the rule file updates the per-turn
   reminder automatically. Cost ~90 tokens/turn. Fails open (missing
   file/marker → baseline only).

3. **Anti-misremember clause in WITHSTAND-CRITICISM**: when a challenge
   concerns a rule, re-read and QUOTE the rule text before assessing
   compliance; never judge against recollection.

**Deferred (story 6.0): AskUserQuestion structural checker.** A
PreToolUse hook matched to `AskUserQuestion` that denies a malformed
call once (kind word missing / multiSelect inconsistent / empty
description) with the checklist as the deny reason; the corrected call
is re-sent and passes deterministically. Deferred by YAGNI: it is
fixed architectural overhead (script + tests + maintenance) against a
violation rate not yet measured after changes 1–2. Build ONLY if the
observation story (5.0) shows violations persisting; otherwise never.

Honest limit: changes 1–3 raise compliance probability; only blocking
could guarantee it, and blocking is rejected. Effectiveness is
verified by observation (story 5.0).

## Relevant Files

- [plugin/commands/start.md](../../plugin/commands/start.md)
  :: MODIFY — RULE:CLEAR-OPTIONS AskUserQuestion-first rewrite +
  CHECKLIST block; RULE:WITHSTAND-CRITICISM quote-verbatim clause
- [plugin/hooks/behavioral-reminder.sh](../../plugin/hooks/behavioral-reminder.sh)
  :: MODIFY — extract + append the checklist block at runtime
- [plugin/hooks/behavioral-reminder.test.sh](../../plugin/hooks/behavioral-reminder.test.sh)
  :: MODIFY — assert checklist content present in baseline output
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: MODIFY — version bump

## Tasks

- [X] 1.0 **User Story:** As an embo user, I want the closing-choice
  rule to lead with a concrete AskUserQuestion contract, so that
  emitting a compliant choice is fill-in work, not principle recall.
  [2/2]
  - [X] 1.1 Rewrite RULE:CLEAR-OPTIONS in `plugin/commands/start.md`
    AskUserQuestion-first: kind in question text, multiSelect from
    kind, mandatory per-option descriptions, recommended-first-only-
    when-genuine, text fallback for >4 options, consequence framing
    [verify: code-only]
      → rewritten per user notes a/b/c (drama, AskUserQuestion
        primary, descriptions always) (2026-07-09)
  - [X] 1.2 Add quote-verbatim clause to RULE:WITHSTAND-CRITICISM:
    rule-compliance challenges are answered against the rule's text,
    never recollection [verify: code-only]
      → clause added to the Do list (2026-07-09)

- [X] 2.0 **User Story:** As an embo user, I want the per-turn banner
  to carry the operative checklist verbatim from the rule file, so the
  rule text is proximal at generation time with one source of truth.
  [2/2]
  - [X] 2.1 Add `<!-- CHECKLIST:CLEAR-OPTIONS -->` block to start.md;
    extract it in `behavioral-reminder.sh` at runtime (awk between
    markers, fail-open) and append to the baseline [verify: auto-test]
      → extraction works; payload verified via jq: baseline + 11-line
        checklist, valid JSON [live] (2026-07-09)
  - [X] 2.2 Extend `behavioral-reminder.test.sh`: checklist header,
    kind words, AskUserQuestion mandate, decide-first test present;
    names + keyword triggers unaffected [verify: auto-test]
      → 10 passed, 0 failed (2026-07-09)

- [X] 3.0 **User Story:** As an embo user, I want the change shipped.
  [2/2]
  - [X] 3.1 Bump `plugin/.claude-plugin/plugin.json` version
    [verify: code-only]
      → 0.1.3 → 0.1.4 (2026-07-09)
  - [X] 3.2 Run the full hook test suite [verify: auto-test]
      → behavioral-reminder 10, approve-compound 168, embo-capture 60,
        fix-hooks 21 — 259 passed, 0 failed (2026-07-09)

- [ ] 4.0 **User Story:** As the maintainer, I want live evidence the
  fix reduces violations. [1/2]
  - [X] 4.1 Confirm the checklist is injected in a real session
    [verify: manual-run-claude]
      → observed live 2026-07-09: the UserPromptSubmit context of the
        session that authored this change carries the checklist,
        pulled from the just-edited start.md
  - [ ] 4.2 Observe across ≥2 real sessions (this repo + one other
    project): closing choices go through AskUserQuestion with kind
    stated, without user reminders; record a claude-mem observation
    with the outcome. If violations persist, open story 6.0.
    [verify: manual-run-claude]

- [ ] 6.0 **User Story (DEFERRED — gated on 4.2):** As an embo user, I
  want malformed AskUserQuestion calls bounced before they reach me.
  [0/2]
  - [ ] 6.1 `plugin/hooks/validate-askuser.sh` (PreToolUse, matcher
    AskUserQuestion): deny when kind word absent / multiSelect
    inconsistent / any description empty; deny reason = the CHECKLIST
    block; kill-switch env var; tests [verify: auto-test]
  - [ ] 6.2 Register in hooks.json; full suite green [verify: auto-test]
