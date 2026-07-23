# hard-harness-action-time-compliance - Task List

## Relevant Files

- [2026-07-23-046-hard-harness-tech-design.md](2026-07-23-046-hard-harness-tech-design.md)
  :: Hard Harness - Technical Design (VQ-verified, critique-corrected)
- [2026-07-23-046-hard-harness-prd.md](2026-07-23-046-hard-harness-prd.md)
  :: Hard Harness - Product Requirements Document
- [cc-bug-tracking.md](cc-bug-tracking.md) :: Claude Code hook-API bugs
  the design is conditioned on (#75915, #19432, #19115)
- [examine-findings.md](examine-findings.md) :: reconciled PRD review
- [plugin/hooks/approve-compound.sh](../../plugin/hooks/approve-compound.sh)
  :: MODIFIED — single matcher-`*` hook; main() if/else; M1-hold + M3
- [plugin/hooks/approve-compound.test.sh](../../plugin/hooks/approve-compound.test.sh)
  :: MODIFIED — hold / M3 / branch-order fixtures
- [plugin/hooks/custodian-halt.sh](../../plugin/hooks/custodian-halt.sh)
  :: CREATE — PostToolUse matcher-`*` (M1 SET + M9 capture)
- [plugin/hooks/custodian-halt.test.sh](../../plugin/hooks/custodian-halt.test.sh)
  :: CREATE — detector / marker / capture fixtures
- [plugin/hooks/harness-rules.json](../../plugin/hooks/harness-rules.json)
  :: CREATE — shipped default rules (2 per class, distinct shapes)
- [plugin/hooks/harness-rules.test.sh](../../plugin/hooks/harness-rules.test.sh)
  :: CREATE — config-driven decision + genericity + boundary fixtures
- [plugin/bin/embo-custodian](../../plugin/bin/embo-custodian)
  :: CREATE — clear-marker wrapper (stable hook-visible head)
- [plugin/bin/embo-custodian.test.sh](../../plugin/bin/embo-custodian.test.sh)
  :: CREATE — wrapper fixtures
- [plugin/commands/custodian-clear.md](../../plugin/commands/custodian-clear.md)
  :: CREATE — `/embo:custodian-clear` command
- [plugin/hooks/hooks.json](../../plugin/hooks/hooks.json)
  :: MODIFIED — PreToolUse Bash→`*`; add PostToolUse `*`
- [.gitignore](../../.gitignore) :: MODIFIED — add `.claude/embo_state/`
- [CLAUDE.md](../../CLAUDE.md) :: MODIFIED — mechanism-level note only

## Notes

- Hook tests follow the existing `*.test.sh` sourceable-function
  pattern: source the script, feed synthetic JSON on stdin, assert
  emitted JSON / exit. Zero model calls.
- `bash plugin/hooks/<name>.test.sh` runs a suite; keep each new suite
  runnable standalone.
- All hooks: `set -uo pipefail`, `trap 'exit 0' ERR`, jq + POSIX shell
  only (no new deps).
- The POC (Story 7) is model-in-the-loop and separate from the
  zero-model unit suites.

## Tasks

- [ ] 1.0 **User Story:** As an embo maintainer, I want all rules
  declared in one runtime config so a new rule of a known shape is added
  by editing JSON, never code — proving the harness is generic, not a
  point solution. [6/0]
  - [ ] 1.1 Write `harness-rules.test.sh`: a rule loader reads
    `harness-rules.json`, merges shipped defaults with an optional
    project `.claude/embo_state/harness-rules.json`, and returns
    `class1`/`class2` rule arrays; malformed JSON → empty + logged (fail
    open) [verify: auto-test]
  - [ ] 1.2 Implement the rule-loader function(s) in a sourceable form
    (reuse the 4-layer merge idea from `approve-compound.sh:load_rules`)
    to pass 1.1 [verify: auto-test]
  - [ ] 1.3 Author `harness-rules.json` with the four seed rules:
    class1 `jq-not-python` (heads+arg+body) and `rg-not-grep`
    (head+flag); class2 `auth-halt` (`stderr_matches`) and
    `destructive-precondition` (`exit_and_tool`) — two distinct shapes
    per class [verify: code-only]
  - [ ] 1.4 Write test: the `signal`/trigger **shape dispatch** — a
    known `signal` type routes to its matcher; an UNKNOWN `signal` type
    fails open and logs "unknown signal shape" (the documented
    genericity boundary) [verify: auto-test]
  - [ ] 1.5 Implement the shape-dispatch to pass 1.4 [verify: auto-test]
  - [ ] 1.6 Write the FR-genericity-test harness: add a 3rd rule per
    class (`uv-not-pip`; `missing-approval-halt`) via JSON only and
    assert both fire with **zero `.sh` change** (diff-guard the scripts)
    [verify: auto-test]

- [ ] 2.0 **User Story:** As a developer, I want a procedural-habit rule
  (CLASS 1) to deny the wrong command at the tool boundary and hand back
  the exact sanctioned substitute, so I follow the rule at action-time
  regardless of what I recall. [4/0]
  - [ ] 2.1 Write tests in `approve-compound.test.sh`: for each class1
    rule, a matching normalized Bash subcommand → `deny` with the rule's
    substitute in `permissionDecisionReason`; a non-matching command →
    unaffected (falls through to existing logic) [verify: auto-test]
  - [ ] 2.2 Implement the M3 check as a sourceable function
    (`class1_check`) reusing `normalize_subcommand`/`split_subcommands`,
    reading rules from Story 1's loader, to pass 2.1 [verify: auto-test]
  - [ ] 2.3 Write test: `SUBSTITUTE_SUPPLY_DISABLED=1` → M3 check is a
    no-op (control-arm switch, FR-8) [verify: auto-test]
  - [ ] 2.4 Implement the disable switch to pass 2.3 [verify: auto-test]

- [ ] 3.0 **User Story:** As a developer, I want a critical-failure
  signal in any tool's output to set an out-of-band halt marker, and a
  hold-check that reads it — the CLASS 2 detection + state, built
  standalone before the hook wiring that uses it. [8/0]
  - [ ] 3.1 Write `custodian-halt.test.sh`: synthetic PostToolUse JSON
    for a Bash tool AND a non-Bash (MCP-style) tool whose `tool_output`
    matches a class2 detector → emits root-level
    `{"decision":"block","reason":<report>}` and writes the marker;
    non-matching output → no marker, no block [verify: auto-test]
  - [ ] 3.2 Implement `custodian-halt.sh` (PostToolUse matcher-`*`):
    set its executable bit; create the marker dir if absent; source a
    shared timestamp helper (a single `iso_now` fn, since the sandbox
    can restrict bare `date` — define it once and reuse across hooks);
    read `tool_name`/`tool_input`/`tool_output`, evaluate each class2
    detector via the shape dispatch (Story 1), on match write the marker
    **atomically** (`> f.tmp && mv f.tmp f`) — to pass 3.1
    [verify: auto-test]
  - [ ] 3.3 Write the HOLD tests for `custodian_hold_check` (a sourceable
    function): marker present → returns halt + report; marker absent →
    no-halt; marker present-but-unparseable → **halt (fail-SAFE), NOT
    no-halt** [verify: auto-test]
  - [ ] 3.4 Implement `custodian_hold_check` (read marker, fail-safe-to-
    halt on corrupt) as a standalone sourceable function to pass 3.3;
    wiring into `main()` happens in Story 4 [verify: auto-test]
  - [ ] 3.5 Write test: `is_exempt` returns true for `Read`/`Grep`/`Glob`
    and for a command whose normalized head is the `embo-custodian`
    wrapper; false otherwise [verify: auto-test]
  - [ ] 3.6 Implement `is_exempt` to pass 3.5 [verify: auto-test]
  - [ ] 3.7 Write test: `CUSTODIAN_HALT_DISABLED=1` → SET and
    hold-check are both no-ops (control-arm switch, FR-8)
    [verify: auto-test]
  - [ ] 3.8 Implement the disable switch to pass 3.7 [verify: auto-test]

- [ ] 4.0 **User Story:** As a developer, I want the PreToolUse hook
  restructured into a single matcher-`*` registration that calls the
  hold-check first (all tools) then the Bash path — so the CLASS 2 gate
  covers every tool and the #75915 updatedInput-discard bug is avoided
  by construction. [2/0]
  - [ ] 4.1 Write the FR-9 branch-order tests (single hook, one
    invocation per case), now that `custodian_hold_check` (Story 3) and
    `class1_check` (Story 2) exist: (a) marker present + non-Bash tool →
    `deny`; (b) marker present + Bash w/ M3 trigger → `deny`, **no
    `updatedInput` emitted**; (c) no marker + allowed Bash →
    `allow`+rewrite intact; (d) no marker + non-Bash → silent
    fallthrough [verify: auto-test]
  - [ ] 4.2 Restructure `approve-compound.sh` `main()`: replace the
    `[ "$TOOL" = "Bash" ] || exit 0` early-exit (line ~423) with an
    if/else — read `tool_name`; call `custodian_hold_check` +
    `is_exempt` first for ALL tools (deny + exit on halt); then run the
    Bash-only path (`class1_check` from Story 2 + existing allow/wrap)
    only when `tool_name == Bash` — to pass 4.1 [verify: auto-test]

- [ ] 5.0 **User Story:** As a developer, I want to clear an active halt
  myself through a dedicated command, with a flap guard that flags a
  recurring false-positive signature — so a stuck or noisy gate never
  silently degrades into a rule I route around. [6/0]
  - [ ] 5.1 Write `embo-custodian.test.sh`: `embo-custodian clear`
    deletes the marker and appends `{rule_id, cleared_ts}` as an NDJSON
    line to `custodian-cleared.log`; `embo-custodian status` reports
    active/none [verify: auto-test]
  - [ ] 5.2 Implement `plugin/bin/embo-custodian` (pattern of
    `embo-deliver`/`embo-corrections`); set the executable bit
    (`chmod +x`) so it is invocable as a bare command on PATH, matching
    the sibling wrappers — to pass 5.1 [verify: auto-test]
  - [ ] 5.3 Write test: flap guard — `custodian-halt.sh` greps
    `custodian-cleared.log` filtered by `rule_id`; same rule cleared
    within N turns/min → report escalates to "possible false-positive
    signature for rule <id>"; different rule's clear does NOT affect it
    (append-log, not overwrite) [verify: auto-test]
  - [ ] 5.4 Implement the flap-guard read in `custodian-halt.sh` to pass
    5.3 [verify: auto-test]
  - [ ] 5.5 Create `plugin/commands/custodian-clear.md`
    (`/embo:custodian-clear`) that runs `embo-custodian clear`
    [verify: code-only]
  - [ ] 5.6 Verify the command end-to-end: trip a halt, run
    `/embo:custodian-clear`, confirm the marker is gone and tools flow
    again [verify: manual-run-claude]

- [ ] 6.0 **User Story:** As an embo maintainer, I want every violation
  captured to a log and the whole harness wired into hooks.json with
  docs and disable switches — so the mechanism is observable,
  installable, and reversible. [7/0]
  - [ ] 6.1 Write test: `custodian-halt.sh` appends one NDJSON line
    (`ts, rule_id, class, mechanism, tool_name, verdict`) per
    violation-shaped signal to `harness-violations.log`, regardless of
    block; no model-facing output from the capture [verify: auto-test]
  - [ ] 6.2 Implement the M9 capture append to pass 6.1
    [verify: auto-test]
  - [ ] 6.3 Update `hooks.json`: change the PreToolUse entry matcher from
    `Bash` to `*` (single registration); add a PostToolUse matcher-`*`
    entry for `custodian-halt.sh` [verify: code-only]
  - [ ] 6.4 Add `.claude/embo_state/` to `.gitignore` [verify: code-only]
  - [ ] 6.5 Document the mechanism in `CLAUDE.md` at the same
    mechanism-level as the existing `approve-compound.sh` entry
    [verify: code-only]
  - [ ] 6.6 Write the user-facing docs (FR-10): `harness-rules.json`
    schema + how to add a rule + `/embo:custodian-clear` usage + manual
    fallback, in README and the command file (NOT CLAUDE.md, per the
    not-a-deliverable rule) [verify: code-only]
  - [ ] 6.7 Verify the full wiring live: with the plugin reloaded, a
    class1 trigger denies + substitutes, and a class2 signal halts + is
    cleared — using only the default `harness-rules.json`
    [verify: manual-run-claude]

- [ ] 7.0 **User Story:** As an embo maintainer, I want a control-vs-
  treatment POC that measures whether each mechanism actually beats a
  stated-but-unenforced rule, and at what token overhead — so we ship
  only mechanisms proven to cause compliance. [5/0]
  - [ ] 7.1 Build the POC harness: fixed CLASS 1 + CLASS 2 elicitation
    scenarios, each run under CONTROL (`*_DISABLED=1`, rule stated) and
    TREATMENT (armed), K≥20 per arm, logging to the FR-6 NDJSON shape
    [verify: code-only]
  - [ ] 7.2 Run the CLASS 1 (jq/yq) arms; record first-tool-call
    compliance (jq/yq vs python/node) per arm [verify: manual-run-claude]
  - [ ] 7.3 Run the CLASS 2 (auth-halt) arms with a stub tool returning
    a canned auth failure; record stop-and-report vs workaround per arm
    [verify: manual-run-claude]
  - [ ] 7.4 Aggregate: treatment−control delta with CI + standing vs
    reactive token overhead (`jq` over the log); report
    compliance-gain-per-standing-token [verify: manual-run-claude]
  - [ ] 7.5 Decision record: for each mechanism, ship / cut / revise
    against the FR-genericity + acceptance bar; write it into the task
    folder [verify: code-only]
