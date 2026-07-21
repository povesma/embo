# 044 Subagent Utilization — Task List

## Relevant Files

- [2026-07-21-044-subagent-utilization-tech-design.md](2026-07-21-044-subagent-utilization-tech-design.md)
  :: Subagent Utilization - Technical Design
- [2026-07-21-044-subagent-utilization-prd.md](2026-07-21-044-subagent-utilization-prd.md)
  :: Subagent Utilization - PRD (Decision Framework is the normative
  source for rule text)
- plugin/commands/start.md :: RULE:DELEGATE + CHECKLIST:DELEGATE
  blocks, incl. the declare-before-explore line (modify)
- plugin/commands/prd.md, tech-design.md, tasks.md, impl.md,
  health.md, check.md, git.md :: Checkpoint blocks (modify)
- plugin/agents/rlm-subcall.md, examine-advisor.md,
  approach-validator.md, visual-qa-reviewer.md :: Description trigger
  sentences (modify)
- plugin/hooks/behavioral-reminder.sh :: CHECKLIST injection + the
  BASELINE rules banner (modify: add DELEGATE tag)

## Notes

- Story 1.0 (the spike) is complete and its finding rejected the
  reactive hook; FR-2 is now the declare-before-explore rule.
- Stories 2.0 and 3.0 both edit RULE:DELEGATE / CHECKLIST:DELEGATE in
  `start.md`; do 3.0's block first, then 2.0 folds the declaration
  line into it — or do them in one pass. They are not independent.
- Stories 4.0 and 5.0 are independent of each other. Story 6.0 last.
- No code is shipped by this feature; all changes are markdown. The
  only test is the CHECKLIST-extraction check (2.2), run against
  `behavioral-reminder.sh` the way `behavioral-reminder.test.sh`
  already does.

## Tasks

- [X] 1.0 **User Story:** As the maintainer, I know whether a
  PreToolUse hook can reach the model mid-turn, so the reactive-hook
  option is decided on fact, not guess
  - [X] 1.1 Write a throwaway PreToolUse spike hook (matcher
    `Read|Grep|Glob`) in the repo's local `.claude/` config (NOT
    `plugin/`) returning `permissionDecision: "allow"` +
    `additionalContext` with a unique sentinel string
    [verify: code-only]
  - [X] 1.2 Live session: trigger Read calls, then ask the model to
    repeat any bracketed reminder text it received; record whether
    the sentinel is visible [verify: manual-run-user]
    → sentinel visible in system-reminder on every Read; allow did
      not block the calls; user confirmed [live] (2026-07-21)
  - [X] 1.3 Record the outcome in this file; remove the spike hook
    [verify: code-only]
    → PreToolUse additionalContext IS model-visible under `allow`.
      A counting hook was then built (14/14 tests) and REJECTED: it
      fires after the counted reads are already in context and cannot
      see intent pre-read. Mechanism changed to the FR-2 declaration
      (story 2.0). Spike + hook artifacts removed. Finding preserved
      in tech-design "Rejected: the reactive nudge hook" (2026-07-21)

- [~] 2.0 **User Story:** As an embo user, the model declares its
  delegation decision before bulk exploration, so the choice is made
  (and visible) before the reads are paid for
  - [X] 2.1 Write the declare-before-explore rule text into the
    RULE:DELEGATE block (story 3.0's file): before bulk exploration,
    emit one line `Delegation: <delegating to X | not delegating,
    because <counter-trigger>>`, then proceed; scope it to multi-file
    exploration only, never per single read [verify: code-only]
  - [X] 2.2 Make the declaration line the one imperative in the
    CHECKLIST:DELEGATE block so `behavioral-reminder.sh` injects it
    every turn [verify: auto-test]
    → hook injects [DELEGATE checklist] with the declaration line;
      behavioral-reminder.test.sh 13 passed, 0 failed [live]
      (2026-07-21)
  - [ ] 2.3 Live check: in a fresh session, give a task that needs
    multi-file exploration; confirm a `Delegation:` line is emitted
    before the reads begin [verify: manual-run-claude]

- [~] 3.0 **User Story:** As an embo user, every session carries the
  delegation decision framework, so the model knows when and how to
  suggest
  - [X] 3.1 Write RULE:DELEGATE block in `plugin/commands/start.md`:
    6 triggers + 6 counter-triggers (PRD Decision Framework
    verbatim-adapted), suggestion protocol (AskUserQuestion only,
    `[delegate:trigger-<n>]` marker, decline suppresses trigger for
    session), handoff checklist, FR-5 verification clause
    [verify: code-only]
  - [X] 3.2 Write CHECKLIST:DELEGATE block (≤60 tokens, pointer
    style); confirm `behavioral-reminder.sh` extraction picks it up
    (awk pattern at `behavioral-reminder.sh:114` matches the new
    block) [verify: auto-test]
    → hook output contains the [DELEGATE checklist] body; existing
      suite 13 passed, 0 failed [live] (2026-07-21)
  - [X] 3.3 Add DELEGATE to the BASELINE rules banner in
    `behavioral-reminder.sh:97` [verify: code-only]
  - [ ] 3.4 New session: banner lists DELEGATE; checklist text
    injected on prompt submit [verify: manual-run-claude]

- [~] 4.0 **User Story:** As a developer in embo commands, I get
  delegation offers at prescribed moments, so high-leverage
  delegation does not depend on model initiative
  - [X] 4.1 Add approval-gate critique checkpoint (trigger 2, cost-
    proportionality clause, marker format) to `prd.md`,
    `tech-design.md`, `tasks.md` [verify: code-only]
  - [X] 4.2 Add checkpoints to `impl.md`: bulk pattern discovery
    (trigger 1) and ≥3-independent-subtasks fan-out (trigger 4);
    state explicitly that prescribed profile-test-agent spawns are
    unchanged [verify: code-only]
  - [X] 4.3 Add troubleshooting-loop checkpoint (trigger 5) to
    `health.md` and `git.md`; `check.md` uses trigger 1 (bulk
    verification reads), not 5 — trigger 5 (troubleshooting loop)
    did not fit a completion-checking command [verify: code-only]
    → all checkpoints written as one-line pointers to RULE:DELEGATE,
      no restated mechanics (2026-07-21)
  - [ ] 4.4 Run one doc command end-to-end; approval gate offers
    the critique with marker [verify: manual-run-claude]

- [X] 5.0 **User Story:** As the model in a free-form turn, I can
  match specialized agents to ad-hoc work, so the shipped agents get
  used beyond their prescribed commands
  - [X] 5.1 Append one free-form trigger sentence to each of the 4
    agent descriptions (`rlm-subcall`, `examine-advisor`,
    `approach-validator`, `visual-qa-reviewer`); no other
    frontmatter changes [verify: code-only]
    → all 4 descriptions gained an "also use ad hoc, outside <cmd>"
      trigger; YAML frontmatter parses for all 4 (2026-07-21)

- [~] 6.0 **User Story:** As the maintainer, the feature is
  documented and proven live, so it can ship in the next release
  - [X] 6.1 README: "Delegation prompts" section — what the user
    sees (`Delegation:` line + subagent offer), how to decline
    (per-session silence), and the tune point (`RULE:DELEGATE`).
    No disable/threshold env — the hook was cut [verify: code-only]
  - [X] 6.2 CHANGELOG entry (Unreleased) describing the behavior;
    version bump deferred to the real release after 6.3
    [verify: code-only]
  - [ ] 6.3 Live end-to-end: a fresh session shows the DELEGATE
    banner, a `Delegation:` line before bulk exploration, a subagent
    offer at a checkpoint, and FR-5 diff verification after a
    delegated edit; evidence recorded here [verify: manual-run-claude]

