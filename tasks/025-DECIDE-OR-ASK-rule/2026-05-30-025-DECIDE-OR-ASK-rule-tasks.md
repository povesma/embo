# 025-DECIDE-OR-ASK-rule — Task List

## Relevant Files

- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Add the `<!-- RULE:DECIDE-OR-ASK -->` section under "Session
  Behavioral Rules", next to REDIRECT-CMD-OUTPUT.
- [.claude/hooks/behavioral-reminder.sh](../../.claude/hooks/behavioral-reminder.sh)
  :: Append `· DECIDE-OR-ASK` to the baseline tag-list.
- [README.md](../../README.md)
  :: Add a row only if a per-rule-tag list exists; otherwise skip
  with a one-line reason.

## Notes

- Same shape as SCAN-CHOICES (015), PLAIN-ENGLISH (023), and
  REDIRECT-CMD-OUTPUT (024): a rule section in `dev:start.md` plus a
  baseline token in the hook. Always-on baseline, not a triggered
  classifier.
- This rule was refined from a NotebookLM deep-research report
  ("Agent Decide-or-Ask Rule Research", notebook
  5178453d-ef1b-4e67-8d51-43e3b80731b3, 29 cited sources). Key inputs:
  the four-level reversibility taxonomy (idempotent / reversible /
  compensable / irreversible), the trapdoor concept (choices that look
  reversible but freeze once data or callers depend on them), and the
  Ask-F1 precision/recall framing (ask only genuine blockers, and ask
  with a recommendation rather than an open question).
- The rule must NOT weaken the existing safety rules. Irreversible and
  shared-state actions (force-push, merge to shared base, delete data,
  send external messages) always require asking — unchanged.
- Built on branch feature/023-plain-english, on top of PLAIN-ENGLISH
  (023) and REDIRECT-CMD-OUTPUT (024); the new section is placed next
  to REDIRECT-CMD-OUTPUT.
- Verification shorthand:
  `echo '{"prompt":"what is the status"}' | bash behavioral-reminder.sh`

## Tasks

- [X] 1.0 **User Story:** As a user of the workflow, I want a
  DECIDE-OR-ASK rule always present in the baseline so the agent
  decides reversible and compensable choices itself by stated criteria,
  escalates only genuine blockers and irreversible / trapdoor actions,
  and when it does ask, brings a recommendation and states whether
  options are exclusive, combinable, or only about order. [3/3]
  - [X] 1.1 Add `<!-- RULE:DECIDE-OR-ASK -->` and a
    `### Decide what you can; escalate only genuine blockers, with a
    recommendation` subsection to `dev:start.md` under "Session
    Behavioral Rules", next to REDIRECT-CMD-OUTPUT. Use the same
    Do / Do not (or labelled-block) format. Cover: (a) act without
    asking on idempotent + reversible actions; (b) act and report on
    compensable actions (commit, push to feature branch, open PR,
    local migration with tested down-script); (c) always ask first on
    irreversible actions and trapdoors (schema shape, public API
    contract, on-disk/wire data format, multi-tenant isolation),
    keeping the existing safety-rule set unchanged; (d) ranking order
    best-practice → long-term outcome → DR-readiness; (e) weighting:
    dev/coding time is cheap, complexity is lowest-value (KISS, YAGNI);
    (f) when asking: escalate only genuine blockers, bring a
    recommendation not an open question, state exclusivity / combinable
    / order, one option per line (cross-ref SCAN-CHOICES).
    [verify: code-only]
  - [X] 1.2 Append `· DECIDE-OR-ASK` to the baseline
    `[RULES ACTIVE: ...]` line in `behavioral-reminder.sh`.
    [verify: code-only]
  - [X] 1.3 Verify: pipe `'{"prompt":"what is the status"}'` into the
    hook; confirm the baseline output contains `DECIDE-OR-ASK` and the
    hook exits 0. Pipe `'{}'` (no prompt field); confirm exit 0 and no
    crash. [verify: manual-run-claude]
    → normal prompt: baseline output contains DECIDE-OR-ASK,
      hookEventName UserPromptSubmit, exit 0; malformed `{}`: baseline
      returned, no crash, exit 0 [live] (2026-05-30)

- [X] 2.0 **User Story:** As a new user reading the README, I want the
  DECIDE-OR-ASK rule documented wherever the other rule tags are
  documented. [1/1]
  - [X] 2.1 Add a DECIDE-OR-ASK row to the README per-rule-tag list if
    one exists; otherwise record a skip with a one-line reason,
    matching how tasks 015, 023, and 024 handled the same case.
    [verify: code-only]
    → skipped: README §Hooks has no per-rule-tag list, only a file-tree
      line and a one-row hooks table entry that does not enumerate
      tokens; nothing to update, same as tasks 015, 023, 024 (2026-05-30)
