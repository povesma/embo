# Subagent Rule Inheritance - Task List

## Relevant Files
- [2026-09-02-055-subagent-rule-inheritance-tech-design.md](2026-09-02-055-subagent-rule-inheritance-tech-design.md)
  :: Subagent Rule Inheritance - Technical Design
- [2026-09-02-055-subagent-rule-inheritance-prd.md](2026-09-02-055-subagent-rule-inheritance-prd.md)
  :: Subagent Rule Inheritance - Product Requirements Document
- [plugin/hooks/subagent-rules.sh](../../plugin/hooks/subagent-rules.sh)
  :: NEW — SubagentStart hook that injects the filtered rule block.
- [plugin/hooks/subagent-rules.test.sh](../../plugin/hooks/subagent-rules.test.sh)
  :: NEW — fixture tests for the injection hook.
- [plugin/hooks/behavioral-reminder.sh](../../plugin/hooks/behavioral-reminder.sh)
  :: Reference — the CHECKLIST extraction + jq JSON-output pattern to reuse.
- [plugin/hooks/approve-compound.sh](../../plugin/hooks/approve-compound.sh)
  :: Reference — the stateless, fail-open hook shape to follow.
- [plugin/commands/start.md](../../plugin/commands/start.md)
  :: Source of the 6 CHECKLIST regions (single source for shared rules).
- [plugin/hooks/hooks.json](../../plugin/hooks/hooks.json)
  :: Modify — register the SubagentStart event.
- [plugin/agents/rlm-subcall.md](../../plugin/agents/rlm-subcall.md)
  :: Modify — add permissionMode: acceptEdits.
- [plugin/agents/session-scout.md](../../plugin/agents/session-scout.md)
  :: Modify — add permissionMode: acceptEdits.
- [plugin/agents/examine-advisor.md](../../plugin/agents/examine-advisor.md)
  :: Modify — add permissionMode: acceptEdits.
- [plugin/agents/approach-validator.md](../../plugin/agents/approach-validator.md)
  :: Modify — add permissionMode: acceptEdits.
- [plugin/agents/visual-qa-reviewer.md](../../plugin/agents/visual-qa-reviewer.md)
  :: Modify — add permissionMode: acceptEdits.

## Notes
- Shell fixture tests follow the repo pattern in
  `plugin/claude-mem/corrections-lib.test.sh` — drive the script with
  synthetic stdin, assert on the emitted `additionalContext` JSON.
- Run a single test file directly: `bash plugin/hooks/subagent-rules.test.sh`.
- The hook is stateless and fail-open (`trap 'exit 0'`), matching the two
  reference hooks — no cross-call state.
- **Story 0 is a blocking gate.** Its live-probe outcome can re-scope or
  cancel the remaining stories; do not start Story 2+ until it passes.

## Tasks

- [X] 0.0 **User Story:** As the embo maintainer, I want the three blocking
  assumptions proven by a live probe before any hook code is written, so
  that implementation is not built on a false premise.
  - [X] 0.1 Register a temporary `UserPromptSubmit` hook that appends the
    incoming `agent_id` (from stdin) to a log file; spawn a Task subagent
    with a trivial prompt; record whether the log gains a subagent-`agent_id`
    entry. Capture `claude --version` alongside. [verify: manual-run-claude]
    → headless 2.1.146 probe (tmp/probe-055): subagent demonstrably spawned,
      hook logged only the main prompt — UserPromptSubmit does NOT fire for
      subagent prompts; payload carries no agent_id field [live] (2026-09-02)
  - [X] 0.2 Record the Assumption-1 verdict in the tech-design: if
    `UserPromptSubmit` does NOT fire in subagents → proceed as designed; if
    it DOES → STOP and re-scope (feature collapses to filtering the existing
    injection). [verify: code-only]
  - [X] 0.3 Register a temporary `SubagentStart` hook that injects a canary
    (`EMBOCANARY_7Q: reply with EMBOCANARY_7Q-SEEN as your first line`);
    give the target agent a long (400+ line) `.md` body; spawn it ~5 times
    with a benign prompt that does not mention the canary. [verify:
    manual-run-claude]
    → 5 headless spawns of a 420-line-body agent; SubagentStart fired 5/5,
      payload carries agent_id + agent_type [live] (2026-09-02)
  - [X] 0.4 Confirm arrival (canary present in the subagent input via
    `claude --debug` hook log) and salience (first output line is
    `EMBOCANARY_7Q-SEEN` across the ~5 runs). Record the pass/fail. [verify:
    manual-run-claude]
    → PASS 5/5 on 2.1.146: arrival proven from each subagent's own
      transcript (stronger than the --debug log), first output line
      EMBOCANARY_7Q-SEEN in all 5; control run canary-free [live]
      (2026-09-02)
  - [X] 0.5 Record the Assumption-2/3 verdict in the tech-design: if salience
    fails with a long body, strengthen D3 (or note the upstream
    `updatedPrompt` dependency) before Story 1. Remove all temporary probe
    hooks and log files. [verify: code-only]
    → salience PASSED, D3 kept as insurance; probe dirs deleted with user
      approval (2026-09-02)

- [X] 1.0 **User Story:** As an embo user, I want a SubagentStart hook that
  injects the correct filtered rule block into every spawned subagent, so
  that subagents run under the main agent's judgment rules without stalling.
  - [X] 1.1 Write the fixture test file `subagent-rules.test.sh` (following
    `corrections-lib.test.sh`): drive the hook with synthetic `SubagentStart`
    stdin and assert the emitted `additionalContext` INCLUDES the
    WITHSTAND-CRITICISM and AVOID-APPROVAL checklist text. [verify:
    auto-test]
    → in suite, passing [live] (2026-09-02)
  - [X] 1.2 Extend the test to assert the output EXCLUDES CLEAR-OPTIONS,
    RESTATE-CORRECTION, FOLD-FIRST, and DELEGATE text. [verify: auto-test]
    → in suite, passing [live] (2026-09-02)
  - [X] 1.3 Extend the test to assert the static preamble (DECIDE-OR-ASK
    "decide, don't stall" + RESEARCH-VERIFY "check docs first") and the
    salience header (D3) are present and lead the block. [verify: auto-test]
    → in suite, passing; also asserts preamble ordering before checklists
      [live] (2026-09-02)
  - [X] 1.4 Extend the test to assert fail-open behavior: with `start.md`
    absent/unreadable, the hook exits 0 and does not crash (emits the
    preamble alone or nothing). [verify: auto-test]
    → in suite, passing (preamble-alone variant chosen) [live] (2026-09-02)
  - [X] 1.5 Extend the test to assert single-source behavior: editing a kept
    region's text in a fixture `start.md` changes the emitted output (FR-5).
    [verify: auto-test]
    → in suite, passing via copied-hook fixture tree [live] (2026-09-02)
  - [X] 1.6 Implement `plugin/hooks/subagent-rules.sh` to pass 1.1–1.5:
    reuse the `behavioral-reminder.sh` awk to extract the 6 regions, drop the
    4 excluded by name, prepend the static preamble under the salience
    header, emit valid JSON via `jq -n`, `trap 'exit 0' ERR`, honor a disable
    env switch. [verify: auto-test]
    → red 14 failures before impl, green after [live] (2026-09-02)
  - [X] 1.7 Run the full test file and confirm all assertions pass. [verify:
    auto-test]
    → 23 passed, 0 failed [live] (2026-09-02)

- [X] 2.0 **User Story:** As an embo user, I want the hook registered so it
  actually fires on every subagent spawn, so that the injection is live in
  the installed plugin.
  - [X] 2.1 Add a `SubagentStart` entry (matcher `*`) to
    `plugin/hooks/hooks.json` invoking `subagent-rules.sh`, matching the
    existing entry style. [verify: code-only]
  - [X] 2.2 Update the `hooks.json` top-level `description` to mention the
    subagent-rule injection. [verify: code-only]
  - [X] 2.3 `/reload-plugins`, spawn any subagent, and confirm from a
    `claude --debug` hook log that `subagent-rules.sh` fired on
    `SubagentStart`. [verify: manual-run-claude]
    → after reload (14 hooks), probe subagent quoted the injected header
      + exactly the 4 kept sections; block confirmed in its transcript
      file (stronger than the --debug log) [live] (2026-09-02)

- [X] 3.0 **User Story:** As an embo user, I want the five shipped agents to
  run under a calibrated permission mode, so that their recoverable actions
  proceed unattended while irreversible actions stay gated.
  - [X] 3.1 Add `permissionMode: acceptEdits` to the frontmatter of
    `rlm-subcall.md`, `session-scout.md`, `examine-advisor.md`,
    `approach-validator.md`, and `visual-qa-reviewer.md`. [verify: code-only]
    → grep confirms the line in all 5 frontmatters (2026-09-02)
  - [X] 3.2 Confirm all five agents load without a frontmatter error after
    `/reload-plugins` (no schema rejection). [verify: manual-run-claude]
    → reload reported 12 agents with no rejection; edited rlm-subcall
      spawned and replied [live] (2026-09-02)

- [X] 4.0 **User Story:** As an embo user, I want end-to-end confirmation
  that a spawned subagent receives and applies the rules and respects the
  safety ceiling, so that the feature demonstrably solves the unattended-run
  problem.
  - [X] 4.1 Spawn a shipped agent on a task with a recoverable choice;
    confirm its transcript shows a `Decide-check:` or `Shape-check:` artifact
    (rules received + applied, Success Metric 2). [verify: manual-run-claude]
    → approach-validator ran a live fail-open verification unattended and
      emitted "Shape-check: needed — <reason>" before a risky-shape call
      (confirmed in its own assistant output) [live] (2026-09-02)
  - [X] 4.2 Spawn an ad-hoc `general-purpose` subagent; confirm the injected
    rule block is present in its context (via `claude --debug`), proving
    coverage beyond the shipped five (FR-4). [verify: manual-run-claude]
    → general-purpose probe listed the 4 kept sections; block confirmed in
      its transcript file [live] (2026-09-02)
  - [X] 4.3 Drive a subagent toward a recoverable action (edit/test) and
    confirm it proceeds without a human prompt; then toward a named
    irreversible action (force-push/merge/delete) and confirm it still stops
    (FR-2 ceiling). [verify: manual-run-claude]
    → recoverable: validator ran 10 unattended tool uses incl. redirects,
      no prompt; irreversible: agent refused a direct `git branch -D`
      instruction, reported it as a blocker, branch confirmed intact
      [live] (2026-09-02)
