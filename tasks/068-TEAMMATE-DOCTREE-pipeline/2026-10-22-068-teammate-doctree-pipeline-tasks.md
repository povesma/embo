# teammate-doctree-pipeline - Task List

## Relevant Files

- [2026-10-21-068-teammate-doctree-pipeline-tech-design.md](2026-10-21-068-teammate-doctree-pipeline-tech-design.md)
  :: Doc-Tree-by-Agents - Technical Design (13 decisions, verification
  table, Story 0 probe list)
- [2026-10-21-068-teammate-doctree-pipeline-prd.md](2026-10-21-068-teammate-doctree-pipeline-prd.md)
  :: Doc-Tree-by-Agents - Product Requirements Document (FR-1..FR-12,
  resolved probe gate, decisions taken)
- [plugin/workflows/doctree.js](../../plugin/workflows/doctree.js)
  :: NEW - orchestration script. Holds the phase sequence, replay loop,
  round and budget counters, and the INLINED validator (it cannot
  import the shell lib or shell out).
- [plugin/commands/doctree.md](../../plugin/commands/doctree.md)
  :: NEW - entry command: resolves all configuration, runs the
  pre-flight, passes everything in via `args`, and holds the
  sequential fallback.
- [plugin/agents/doctree-phase.md](../../plugin/agents/doctree-phase.md)
  :: NEW - the parameterized phase runner spawned by both paths.
- [plugin/lib/doctree-lib.sh](../../plugin/lib/doctree-lib.sh)
  :: NEW - shared pure functions for the COMMAND and fallback paths:
  model resolution, document path construction, amendment validation.
- [plugin/lib/doctree-lib.test.sh](../../plugin/lib/doctree-lib.test.sh)
  :: NEW - fixture tests for `doctree-lib.sh`, and the parity fixtures
  shared with the inlined JS validator.
- [plugin/lib/branch-task-lib.sh](../../plugin/lib/branch-task-lib.sh)
  :: Pattern for the shared library: header naming consumers, no
  output, no side effects, no exits.
- [plugin/profiles/default.yaml](../../plugin/profiles/default.yaml)
  :: Add the commented `doctree:` block; the other four get bare ones.
- [plugin/commands/prd.md](../../plugin/commands/prd.md)
  :: Unattended branch at its mandatory question steps.
- [plugin/commands/tech-design.md](../../plugin/commands/tech-design.md)
  :: Unattended branch at `:133` and `:371`.
- [plugin/commands/tasks.md](../../plugin/commands/tasks.md)
  :: Unattended branch at `:91` AND at the Step 6 approval stop
  (`:114-118`, restated `:232`) - two distinct gates.
- [plugin/commands/profile.md](../../plugin/commands/profile.md)
  :: Display the new `doctree:` block.
- [plugin/commands/research/examine.md](../../plugin/commands/research/examine.md)
  :: Pattern for the entry command: thin spawner, hard stop on
  degradation.
- [plugin/agents/examine-advisor.md](../../plugin/agents/examine-advisor.md)
  :: The review agent used for both passes.
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: The `workflows` field, if the default location is not used.
- [CLAUDE.md](../../CLAUDE.md)
  :: File-structure section and the command count (20 to 21).
- [README.md](../../README.md) :: Command table and usage section.
- [CHANGELOG.md](../../CHANGELOG.md) :: Release entry.

## Notes

- **The workflow script is isolated.** It cannot read the profile, call
  `doctree-lib.sh`, shell out, touch the filesystem, `import()`, or
  call `new Date()` / `Date.now()` / `Math.random()`. EVERYTHING it
  needs arrives through `args`, resolved by the entry command. Its
  validator is an inlined JS copy, kept in step with the shell library
  by shared fixtures (2.10).
- Shell libraries ship with a sibling `*.test.sh` run by
  `bash <file>.test.sh`.
- `embo-profile get` takes a dotted path, so the field is
  `doctree.models.tech_design` with an underscore.
- Shipped files under `plugin/` must not reference task numbers or
  `tasks/` paths. Hook scripts, bin wrappers and test scripts are
  exempt.
- Story 7 (entry command) is sequenced BEFORE story 8 (back-pressure)
  because the latter needs the arguments the command resolves.
- Review passes and deterministic gates (story 6) are deliberately
  SEPARATE from back-pressure (story 8), so that withdrawing
  back-pressure under 8.11 does not remove FR-5.

## TDD Planning Guidelines

Tests cover the code that actually executes. The workflow script's
inlined validator is tested through parity fixtures (2.10), not through
the shell library alone.

## Tasks

- [ ] 1.0 **User Story:** As the implementer, I want the remaining
  platform unknowns closed with recorded evidence, so that no story is
  built on an assumption that turns out false [4/0]
  - [X] 1.1 Record the probe results already obtained, citing the PRD
    Probe Gate by table row, and capture `claude --version` alongside
    each. Mark P-2 (rule hook fires for stages), P-3 (no slash command;
    Skill loads the body) and P-5 (model parameter accepted) CLOSED
    [verify: code-only]
  - [X] 1.2 Mark P-4 CLOSED-WITH-CAVEAT, not closed: the run showed a
    write that did not stall, which is not the probe the tech-design
    asks for. Record the open part: give a stage a tool OUTSIDE the
    allowlist and observe whether it stalls [verify: manual-run-claude]
  - [~] 1.3 Probe the permission-stall case from 1.2 and record the
    outcome [verify: manual-run-claude]
    (RAN under 2.1.306: a stage's un-allowlisted `touch /Users/Shared/...`
    ran with no prompt, exit 0 — but CONFOUNDED: the stage inherits the
    session's permission mode and this run was in an auto-approving mode,
    so "no stall" is not evidence about a default-mode run. A clean probe
    needs a default-mode session and stays OPEN. Recorded in the
    tech-design Story 0 Results.)
  - [X] 1.4 If either probe fails, stop and report which requirement it
    invalidates before any further story starts [verify: code-only]
    (Assessed: the confounded 1.3 result invalidates NO requirement.
    FR-10 already assumes a stall is possible and guards it with the
    pre-flight that enumerates required allow rules; the probe makes that
    enumeration load-bearing rather than redundant. No story is blocked.)

- [X] 2.0 **User Story:** As an embo user, I want the doc-tree
  configuration to live in my profile, so that model choice, escalation
  and limits are set once rather than retyped per run [0/10]
  - [X] 2.1 Write fixture tests for `doctree_resolve_model <phase>`:
    profile value when set, built-in default when the field or the
    profile is absent [verify: auto-test]
  - [X] 2.2 Implement `doctree_resolve_model` in
    `plugin/lib/doctree-lib.sh` [verify: auto-test]
  - [X] 2.3 Write fixture tests for `doctree_phase_doc_path <taskdir>
    <slug> <phase>` across all three phases [verify: auto-test]
    (Signature revised to `doctree_phase_doc_path <taskdir> <run-date>
    <slug> <phase>` — a run-date arg was added so the path matches the
    established `<date>-<slug>-<suffix>.md` convention; the workflow
    script cannot call `new Date()`, so the caller supplies the date.
    Recorded in the tech-design.)
  - [X] 2.4 Implement `doctree_phase_doc_path` [verify: auto-test]
  - [X] 2.5 Add the commented `doctree:` block to `default.yaml`:
    `models` (prd/tech_design/tasks), `escalation`, `round_cap`,
    `budget.max_agents`, and the reviewer model family
    [verify: code-only]
    (reviewer model family shipped as `reviewer_model_family: sonnet`,
    per the tech-design's "both passes run the same family (sonnet)".)
  - [X] 2.6 Add bare `doctree:` blocks to `quality.yaml`, `fast.yaml`,
    `minimal.yaml`, `research.yaml` per the tech-design defaults table
    [verify: code-only]
  - [X] 2.7 Verify `embo-profile get` returns the expected value for
    every field in every shipped profile, and `""` when absent
    [verify: auto-test]
    (36 assertions in doctree-lib.test.sh, all five profiles + absent
    field; skips cleanly if yq is unavailable.)
  - [X] 2.8 Implement the `escalation` modes themselves - `collect`
    (record and finish) and `halt` (stop at the first blocked item) -
    not merely the field [verify: auto-test]
    (as `doctree_should_halt <mode> <blocked-count>`: rc 0 halt, 1
    continue, 2 unknown mode.)
  - [X] 2.9 Update `plugin/commands/profile.md` so the `doctree:` block
    appears in profile output, and extend its tests [verify: auto-test]
    (added a Doc-tree line to the display; extended embo-profile.test.sh
    with doctree.* read assertions incl. absent-block → empty.)
  - [X] 2.10 Write the parity fixtures: one fixture set exercised by
    BOTH `doctree_validate_amend` and the inlined JS validator, so the
    two cannot drift [verify: auto-test]
    (plugin/lib/doctree-amend-fixtures.json: 10 cases, 3 valid / 7
    rejected, covering each D7 reject reason; a fixture-integrity test
    guards them now, the two validators consume them in Stories 5.5/8.)

- [ ] 3.0 **User Story:** As the orchestration, I want one phase-runner
  agent that both execution paths spawn, so that phase behavior is
  defined once rather than duplicated [7/0]
  - [X] 3.1 Create `plugin/agents/doctree-phase.md` frontmatter:
    `model: inherit`, `permissionMode: acceptEdits`, and a `tools:`
    list limited to what a planning phase needs [verify: code-only]
    (tools: Read/Write/Edit/Grep/Glob/Bash, the two claude-mem search
    tools, the Context7 pair, SendMessage.)
  - [X] 3.2 Write the input contract: phase name, task directory,
    feature slug, mode (`full` | `section-scoped`), amendment records
    [verify: code-only]
    (plus command_file, skip_steps, sections, upstream_docs; partial
    brief → immediate blocked return, no guessing.)
  - [X] 3.3 Write the output contract with a FIXED-SHAPE digest:
    name every field, and state that document bulk stays on disk and
    never enters the return value [verify: code-only]
    (document/summary/decisions_taken/blocked/amend/canary; decisions_taken
    > 0 required when skip_steps was non-empty.)
  - [X] 3.4 Write the standing instruction to decide-and-log rather
    than stall, reaching phase instructions via the Skill tool
    [verify: code-only]
    (sets EMBO_DOCTREE_UNATTENDED so the phase command takes its own
    unattended branch — the Story 4 mode and this agent agree on the
    signal.)
  - [X] 3.5 Add the FR-3 canary: the agent must echo a string that only
    the injected rule block contains, so a silent injection failure is
    caught (the hook fails open) [verify: auto-test]
    (canary phrase `BINDING SUBAGENT RULES`; a test asserts the agent's
    canary phrase matches the phrase subagent-rules.sh actually injects,
    so the canary cannot test a phrase the hook never sends.)
  - [X] 3.6 Confirm the agent body contains no task numbers and no
    `tasks/` paths, via a check in `doctree-lib.test.sh`
    [verify: auto-test]
    (grep for tasks/<digit> and bare task-number/Story refs, both 0; the
    literal placeholder tasks/<nnn>-<SLUG>/ is allowed.)
  - [ ] 3.7 Spawn the agent on a throwaway slug and confirm it produces
    a document, a digest matching 3.3's shape, and the 3.5 canary
    [verify: manual-run-claude]

- [ ] 4.0 **User Story:** As a spawned phase, I want an unattended mode
  in each planning command, so that a question I cannot ask becomes a
  recorded blocked item instead of a stall [6/0]
  - [X] 4.1 Add the unattended branch to `plugin/commands/prd.md`,
    recording a blocked item and continuing [verify: code-only]
    (Unattended-mode box at Step 4 "Ask Clarifying Questions"; gated on
    the env var `EMBO_DOCTREE_UNATTENDED`.)
  - [X] 4.2 Add the unattended branch to `tech-design.md` at `:133` and
    `:371` [verify: code-only]
    (Box at Step 5; parenthetical on the Final-Instructions restatement.)
  - [X] 4.3 Add the unattended branch to `tasks.md` at its clarifying
    question AND at the Step 6 "Go" approval stop - two distinct gates
    [verify: code-only]
    (Box at Step 4 covers both gates; a direct exception on Step 6 itself
    and on the Interaction-Model restatement.)
  - [ ] 4.4 Prove FR-11 on one command, in a spawned stage, with a
    pre-seeded undecidable question: same section headings, a
    Decisions-taken block, and a BLOCKED entry present
    [verify: manual-run-claude]
  - [ ] 4.5 Confirm separately that an interactive run of the same
    command is unchanged [verify: manual-run-claude]
  - [X] 4.6 Confirm by grep that the unattended branch fires only when
    the mode is set, never by default [verify: code-only]
    (Mode signal: the env var `EMBO_DOCTREE_UNATTENDED`. grep over all
    three commands shows every "unattended" reference names the variable;
    none fires by default. No task-number/`tasks/` refs introduced.)

- [ ] 5.0 **User Story:** As an embo user, I want the phase sequence and
  its limits enforced by the runtime, so that the round cap and budget
  are mechanical rather than prose the model may ignore [8/0]
  - [ ] 5.1 Create `plugin/workflows/doctree.js` with its `meta` block
    and the FULL `args` contract: task directory, slug, run date,
    per-phase models, escalation mode, round cap, max agents, reviewer
    family. The script resolves none of these itself
    [verify: code-only]
  - [ ] 5.2 Implement the three authoring stages in sequence, each
    spawning the phase agent with its per-stage model from `args`
    [verify: manual-run-claude]
  - [ ] 5.3 Implement the agent-budget counter and unit-test it against
    its threshold [verify: auto-test]
  - [ ] 5.4 Implement the round counter as a GLOBAL count, not
    per-phase, and unit-test it [verify: auto-test]
  - [ ] 5.5 Implement the inlined JS amendment validator, passing the
    2.10 parity fixtures [verify: auto-test]
  - [ ] 5.6 Confirm the script calls no `new Date()`, `Date.now()`,
    `Math.random()` or `import()`, touches no filesystem, and shells
    out nowhere [verify: auto-test]
  - [ ] 5.7 Register the workflow: add the `workflows` field to
    `plugin.json` if the default location is not used
    [verify: code-only]
  - [ ] 5.8 Run the workflow end to end on a throwaway feature and
    confirm all three documents appear with their expected section
    headings [verify: manual-run-claude]

- [ ] 6.0 **User Story:** As an embo user, I want every phase reviewed
  by two passes and by checks that need no judgement, so that no phase
  is graded only by a context sharing its author's biases [5/0]
  - [ ] 6.1 Define the findings schema: phase, target section,
    severity, status (open/resolved), with "significant" as a severity
    threshold [verify: code-only]
  - [ ] 6.2 Implement the two review passes per phase, spawned by the
    lead and never by the authoring agent, using the configured
    reviewer model family [verify: manual-run-claude]
  - [ ] 6.3 Write fixtures for the six deterministic gates
    [verify: auto-test]
  - [ ] 6.4 Implement the six gates: every requirement maps to an
    acceptance criterion, every cited `file:line` resolves, every
    requirement appears in the verification table [verify: auto-test]
  - [ ] 6.5 Verify a reviewer is never the authoring agent, by
    definition identity [verify: auto-test]

- [ ] 7.0 **User Story:** As an embo user, I want the run to show me its
  configuration and refuse to start when it would stall, so that an
  unattended run does not stop halfway waiting for a permission dialog
  [9/0]
  - [ ] 7.1 Create `plugin/commands/doctree.md` following
    `research/examine.md`'s thin-spawner pattern [verify: code-only]
  - [ ] 7.2 Implement argument parsing: feature slug, per-phase model
    overrides, escalation override [verify: auto-test]
  - [ ] 7.3 Implement configuration resolution - read every profile
    field, apply overrides - and pass the result into the workflow via
    `args` [verify: auto-test]
  - [ ] 7.4 Verify an argument override reaches the spawn call and wins
    over the profile value [verify: auto-test]
  - [ ] 7.5 Implement the pre-flight configuration report, showing each
    model's provenance (profile or override), emitted BEFORE any spawn
    [verify: manual-run-claude]
  - [ ] 7.6 Implement the permission pre-flight: list the exact rules
    needed, refuse to start when one is missing, name what to add
    [verify: manual-run-claude]
  - [ ] 7.7 Implement the MCP precondition check, refusing to start when
    the review server is unreachable [verify: manual-run-claude]
  - [ ] 7.8 Implement the closing report: blocked items collected and
    presented together, rounds taken, and token usage
    [verify: manual-run-claude]
  - [ ] 7.9 Confirm the command body contains no task numbers and no
    `tasks/` paths [verify: auto-test]

- [ ] 8.0 **User Story:** As an embo user, I want a downstream finding
  to amend an upstream document only with evidence and a way back, so
  that review feedback converges on something true instead of
  propagating a plausible error [11/0]
  - [X] 8.1 Write fixture tests for `doctree_validate_amend`: rejects an
    uncited record, rejects a malformed record, accepts a well-formed
    one with a resolvable `file:line` or URL [verify: auto-test]
    (Driven from the shared parity fixtures: all 10 cases checked against
    their expected verdict, plus empty/unparseable edge cases. The
    "resolvable file:line/URL" part is the live check, out of the
    mechanical validator's scope by design — the fixtures use well-formed
    citations and the mechanical check verifies presence/shape.)
  - [X] 8.2 Implement `doctree_validate_amend` in `doctree-lib.sh`
    [verify: auto-test]
    (jq-based: required fields present+non-empty, target/severity/status
    enums; rc 0 valid, 1 rejected, 2 usage/parse error. Mirrors the rules
    the inlined JS validator will share via the fixtures. NOTE: Stories
    8.3-8.11 — run-state, amend/revert/replay paths — stay blocked on the
    Story 5 workflow script and Story 7's resolved args.)
  - [ ] 8.3 Implement the run-state artifact: round number, per-phase
    status, open findings, and `prior_state` per amendment
    [verify: auto-test]
  - [ ] 8.4 Implement the amendment path: an uncited AMEND is rejected
    by the script's inlined validator and the target document is left
    byte-identical [verify: auto-test]
  - [ ] 8.5 Implement the revert path, restoring a document section
    verbatim from saved prior state [verify: auto-test]
  - [ ] 8.6 Implement section-scoped replay and prove by diff that an
    amendment changes ONLY the sections its finding targets
    [verify: auto-test]
  - [ ] 8.7 Implement the termination rule: replay while findings are at
    or above the threshold, stop for approval after round 2 with
    findings still open, and exempt the closing open-items write as
    bookkeeping [verify: auto-test]
  - [ ] 8.8 Verify a completed run has no open "infeasible" finding
    against a requirement, and every amendment carries a resolvable
    citation [verify: manual-run-claude]
  - [ ] 8.9 Run the three gate checks that decide FR-6's fate: (a) a
    seeded uncited AMEND is rejected and the target is byte-identical,
    (b) amend-then-revert restores the section verbatim, (c) a run
    seeded with permanent findings stops at round 2
    [verify: auto-test]
  - [ ] 8.10 If all three pass, record the evidence in the tech-design
    and continue. If any fails, stop and write a short report naming
    the failed condition and its evidence, for user sign-off
    [verify: manual-run-user]
  - [ ] 8.11 On a sign-off to withdraw: remove the AMEND path, KEEP the
    review passes and gates from story 6, and replace back-pressure
    with the closing human gate [verify: manual-run-claude]

- [ ] 9.0 **User Story:** As an embo user, I want a run to survive
  interruption and to degrade loudly, so that a failure costs me a
  restart rather than the whole run [7/0]
  - [ ] 9.1 Implement the run-state reader: a resumed run recovers the
    round number and open findings [verify: auto-test]
  - [ ] 9.2 Implement resume: detect existing documents and restart
    from the first missing phase [verify: auto-test]
  - [ ] 9.3 Test resume by interrupting a run after phase 1 and
    restarting it [verify: manual-run-claude]
  - [ ] 9.4 Implement the sequential fallback in `doctree.md`, spawning
    the same phase agent directly in order [verify: manual-run-claude]
  - [ ] 9.5 Detect workflow availability, select the fallback
    automatically, and state in the report which path is running
    [verify: manual-run-claude]
  - [ ] 9.6 Verify the fallback produces the same three documents, and
    honors the round cap and budget, on the same input
    [verify: manual-run-claude]
  - [ ] 9.7 Cover the degradation matrix, each failing loudly with its
    reason: `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, an organization
    allowlist substituting a model, workflows disabled, the MCP server
    unreachable, a missing permission rule [verify: manual-run-claude]

- [ ] 10.0 **User Story:** As a prospective embo user, I want the new
  command documented, so that I can discover it and know what it costs
  [6/0]
  - [ ] 10.1 Add the command to the README command table
    [verify: code-only]
  - [ ] 10.2 Write a README section naming the profile fields and the
    exact permission rules a run needs, verbatim [verify: code-only]
  - [ ] 10.3 Document the cost: a baseline run is three phases plus six
    review passes, and replay rounds are the dominant multiplier
    [verify: code-only]
  - [ ] 10.4 Measure one real run's token cost and record the figure
    rather than asserting a published multiple
    [verify: manual-run-claude]
  - [ ] 10.5 Update CLAUDE.md's file-structure section and the command
    count [verify: code-only]
  - [ ] 10.6 Add the CHANGELOG entry, one or two lines, stating the
    capability a user gets [verify: code-only]
  - [ ] 10.7 Run the full hook and library test suites to confirm
    nothing regressed [verify: auto-test]

## Summary

10 user stories, 74 subtasks. Story 1.0 is a blocking gate. Story 8.9
and 8.10 decide whether back-pressure ships at all: if any of the three
gate checks fails, 8.11 withdraws it while keeping story 6's review
passes and deterministic gates intact.
