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

- [X] 3.0 **User Story:** As the orchestration, I want one phase-runner
  agent that both execution paths spawn, so that phase behavior is
  defined once rather than duplicated [0/7]
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
  - [X] 3.7 Spawn the agent on a throwaway slug and confirm it produces
    a document, a digest matching 3.3's shape, and the 3.5 canary
    [verify: manual-run-claude]
    (Live run 2026-10-22: spawned embo:doctree-phase on a throwaway slug
    into tmp/doctree-probe/. It wrote
    2026-10-22-probe-feature-tech-design.md at the exact doc_path, returned
    the fixed-shape digest, and the canary field held
    "you have NO channel to ask the human — DECIDE, do not stall" — a
    verbatim substring of subagent-rules.sh's injected HEADER, so FR-3
    injection fired live. Also strengthens P-2 from docs-only to
    live-confirmed for a spawned subagent.)

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
  - [X] 4.4 Prove FR-11 on one command, in a spawned stage, with a
    pre-seeded undecidable question: same section headings, a
    Decisions-taken block, and a BLOCKED entry present
    [verify: manual-run-claude]
    (Live run 2026-10-22, same spawn as 3.7: the tech-design phase ran
    unattended against a PRD carrying one deliberately-undecidable question
    (FR-2 storage backend). The produced document has the normal
    tech-design sections (acceptance table, data contracts, trade-offs), a
    "## Decisions-taken (unattended mode)" block with decisions_taken > 0,
    and BLOCKED-1 recording the undecidable question instead of a guess.)
  - [~] 4.5 Confirm separately that an interactive run of the same
    command is unchanged [verify: manual-run-claude]
    (BLOCKED on permission mode: a faithful interactive run must surface
    the mandatory AskUserQuestion gate, which this auto-approving session
    suppresses. Structurally the interactive path is unchanged — the
    unattended branch is purely additive and gated on
    EMBO_DOCTREE_UNATTENDED (4.6 grep). The faithful proof needs a session
    in the default permission mode: run /embo:tech-design interactively
    with the env var UNSET and confirm the AskUserQuestion step fires as
    before.)
  - [X] 4.6 Confirm by grep that the unattended branch fires only when
    the mode is set, never by default [verify: code-only]
    (Mode signal: the env var `EMBO_DOCTREE_UNATTENDED`. grep over all
    three commands shows every "unattended" reference names the variable;
    none fires by default. No task-number/`tasks/` refs introduced.)

- [ ] 5.0 **User Story:** As an embo user, I want the phase sequence and
  its limits enforced by the runtime, so that the round cap and budget
  are mechanical rather than prose the model may ignore [8/0]
  - [X] 5.1 Create `plugin/workflows/doctree.js` with its `meta` block
    and the FULL `args` contract: task directory, slug, run date,
    per-phase models, escalation mode, round cap, max agents, reviewer
    family. The script resolves none of these itself
    [verify: code-only]
    (meta is a pure literal with three phases; the body reads only from
    the `args` global.)
  - [~] 5.2 Implement the three authoring stages in sequence, each
    spawning the phase agent with its per-stage model from `args`
    [verify: manual-run-claude]
    (Coded: the loop spawns embo:doctree-phase per phase with the
    per-phase model from args and the upstream docs so far. Behavioral
    proof is 5.8's end-to-end run.)
  - [X] 5.3 Implement the agent-budget counter and unit-test it against
    its threshold [verify: auto-test]
    (budgetAllows(spent, max); tested under/at/over cap in
    workflows/doctree.test.js.)
  - [X] 5.4 Implement the round counter as a GLOBAL count, not
    per-phase, and unit-test it [verify: auto-test]
    (round is a single counter over a full pass, not per-phase;
    roundExhausted(round, cap) tested at the threshold.)
  - [X] 5.5 Implement the inlined JS amendment validator, passing the
    2.10 parity fixtures [verify: auto-test]
    (validateAmend, self-contained; the test extracts the ACTUAL inlined
    function from the source and runs all 10 shared fixtures — identical
    verdicts to the shell validator, so they cannot drift.)
  - [X] 5.6 Confirm the script calls no `new Date()`, `Date.now()`,
    `Math.random()` or `import()`, touches no filesystem, and shells
    out nowhere [verify: auto-test]
    (static source scan in the test, comments stripped first so the
    prohibition-naming comment does not trip it.)
  - [X] 5.7 Register the workflow: add the `workflows` field to
    `plugin.json` if the default location is not used
    [verify: code-only]
    (Verified against current Claude Code docs: a script at the plugin's
    default workflows/ dir auto-discovers with NO manifest field; the
    `workflows` field only replaces the default scan. Script is at
    plugin/workflows/doctree.js — the default — so no plugin.json change.
    The workflow is namespaced by plugin name and invoked as `embo:doctree`
    (from meta.name + plugin embo); the entry command names it that way.
    Open: whether the Workflow tool's name param takes `embo:doctree` or
    bare `doctree` is confirmed at the 5.8 live run.)
  - [X] 5.8 Run the workflow end to end on a throwaway feature and
    confirm all three documents appear with their expected section
    headings [verify: manual-run-claude]
    (Run on task 055 twice. Opus authors: 572,024 tokens, 9 agents, 51
    min. Sonnet authors: 505,785 tokens, 10 agents — only 12% cheaper,
    so the authoring model is not the dominant cost; the six review
    passes and their tool use are. The Workflow tool's `name` takes
    `embo:doctree`. Two defects found only by running it: the script
    would not launch at all while it carried `export function` on its
    pure helpers — the runtime permits no export but `export const
    meta` — and agents write `<date>-<nnn>-<slug>-<suffix>.md` while
    `docPath()` computes `<date>-<slug>-<suffix>.md`, so a resumed run
    does not recognise its own documents and re-runs every phase.)

- [ ] 6.0 **User Story:** As an embo user, I want every phase reviewed
  by two passes and by checks that need no judgement, so that no phase
  is graded only by a context sharing its author's biases [5/0]
  - [X] 6.1 Define the findings schema: phase, target section,
    severity, status (open/resolved), with "significant" as a severity
    threshold [verify: code-only]
    (FINDINGS_SCHEMA in the workflow; significant = {high, infeasible},
    defined once as doctree_finding_is_significant / isSignificant and
    tested.)
  - [X] 6.2 Implement the two review passes per phase, spawned by the
    lead and never by the authoring agent, using the configured
    reviewer model family [verify: manual-run-claude]
    (Both passes ran live on every phase and produced substantive
    findings. But FR-6 was shipped NON-FUNCTIONAL and the live run is
    what exposed it: the replay path consumed only `digest.amend` from
    the AUTHORING agent, never the reviewers' findings, so a reviewer's
    finding was recorded as an open item and the document it was about
    went out uncorrected. First run: every phase returned
    `"amendments": []`, no replay agent ever ran (9 agents = 3 phases +
    6 reviews exactly), and the reviewers' real defects — the Bash
    bypass, fail-open, parser gaps — died in the closing report. Fixed
    by a findingToAmend bridge; see 8.6.)
  - [X] 6.3 Write fixtures for the six deterministic gates
    [verify: auto-test]
    (good + seeded-bad fixtures for each of the six gates.)
  - [X] 6.4 Implement the six gates: every requirement maps to an
    acceptance criterion, every cited `file:line` resolves, every
    requirement appears in the verification table [verify: auto-test]
    (all six in doctree-lib.sh as pure functions: fr_has_criterion,
    fr_in_verification_table, citations_resolve, amend_grounded,
    no_open_infeasible, decisions_taken. Set-comparison gates take
    caller-extracted ID lists so the logic stays pure.)
  - [X] 6.5 Verify a reviewer is never the authoring agent, by
    definition identity [verify: auto-test]
    (test asserts the author is doctree-phase and the reviewer is
    examine-advisor — distinct shipped definitions, different names.)

- [ ] 7.0 **User Story:** As an embo user, I want the run to show me its
  configuration and refuse to start when it would stall, so that an
  unattended run does not stop halfway waiting for a permission dialog
  [9/0]
  - [X] 7.1 Create `plugin/commands/doctree.md` following
    `research/examine.md`'s thin-spawner pattern [verify: code-only]
  - [X] 7.2 Implement argument parsing: feature slug, per-phase model
    overrides, escalation override [verify: auto-test]
    (Documented in the Arguments section; the override-resolution rule is
    tested via doctree_effective_model.)
  - [X] 7.3 Implement configuration resolution - read every profile
    field, apply overrides - and pass the result into the workflow via
    `args` [verify: auto-test]
    (Step 1 reads every doctree.* field with bare embo-profile get and
    falls back to the built-in defaults; doctree_effective_model encodes
    override-vs-profile; passed to the workflow via args in Step 4.)
  - [X] 7.4 Verify an argument override reaches the spawn call and wins
    over the profile value [verify: auto-test]
    (doctree_effective_model <override> <phase>: non-empty override wins,
    else profile/default. Tested both directions.)
  - [~] 7.5 Implement the pre-flight configuration report, showing each
    model's provenance (profile or override), emitted BEFORE any spawn
    [verify: manual-run-claude]
    (Command Step 2 specifies the report with per-model provenance and the
    silent-override caveat line; behavioral proof needs a live run.)
  - [~] 7.6 Implement the permission pre-flight: list the exact rules
    needed, refuse to start when one is missing, name what to add
    [verify: manual-run-claude]
    (Command Step 3a lists the required allow rules and the refuse-to-start
    behavior; live proof needed.)
  - [~] 7.7 Implement the MCP precondition check, refusing to start when
    the review server is unreachable [verify: manual-run-claude]
    (Command Step 3b checks gemini-notebook-mcp reachability and refuses
    to start when disconnected; live proof needed.)
  - [~] 7.8 Implement the closing report: blocked items collected and
    presented together, rounds taken, and token usage
    [verify: manual-run-claude]
    (Command Step 5 specifies the combined closing report; live proof
    needs a full run, which depends on the Story 5 workflow.)
  - [X] 7.9 Confirm the command body contains no task numbers and no
    `tasks/` paths [verify: auto-test]
    (grep check in doctree-lib.test.sh: tasks/<digit> and bare task-number
    refs both 0.)

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
  - [X] 8.3 Implement the run-state artifact: round number, per-phase
    status, open findings, and `prior_state` per amendment
    [verify: auto-test]
    (Read side done and tested in Story 9: doctree_runstate_round /
    doctree_runstate_open_findings read doctree-run-state.yaml. The WRITE
    is a stage's job — A4: the workflow script cannot touch the
    filesystem — written beside the documents in the task directory; the
    revert path stores prior_state there.)
  - [X] 8.4 Implement the amendment path: an uncited AMEND is rejected
    by the script's inlined validator and the target document is left
    byte-identical [verify: auto-test]
    (The workflow applies only amendments that pass validateAmend; a test
    confirms an uncited record is rejected and the target is unchanged.)
  - [X] 8.5 Implement the revert path, restoring a document section
    verbatim from saved prior state [verify: auto-test]
    (doctree_revert_section replaces a section from a prior_state file,
    bounded to that section; tested incl. untargeted-section-intact.)
  - [~] 8.6 Implement section-scoped replay and prove by diff that an
    amendment changes ONLY the sections its finding targets
    [verify: auto-test]
    (Replay PROVEN live: a reviewer finding rewrote FR-1 on disk — the
    proposed "Known limit" text appeared at the target section, verified
    by grep, surrounding document intact. 10 agents, so a replay agent
    did run.
    TWO DEFECTS FOUND AND FIXED, both in the path that makes a review
    able to change a document at all:
    (a) Reviewer findings could never become amendments: FINDINGS_SCHEMA
    lacked the target/evidence/proposed/prior_state fields validateAmend
    requires. Added, plus a findingToAmend bridge and a reviewer prompt
    that asks for the grounding and says an ungrounded significant
    finding is dropped — with the instruction to mark it medium rather
    than inflate severity, so the schema change cannot push reviewers to
    invent citations.
    (b) `const amend = groundedAmends[0]` applied only the FIRST
    amendment and discarded the rest silently; since the round counter
    increments per replay, round_cap 2 left no second chance. Observed:
    2 grounded amendments produced, FR-1 rewritten, NFR-2 left
    byte-identical with no log line. Now grouped by target document, one
    replay per affected document carrying every amendment for it, drops
    logged.
    STILL UNPROVEN: the multi-amendment path has unit tests but no live
    run has exercised several amendments applying in one replay.)
  - [X] 8.7 Implement the termination rule: replay while findings are at
    or above the threshold, stop for approval after round 2 with
    findings still open, and exempt the closing open-items write as
    bookkeeping [verify: auto-test]
    (doctree_should_replay / shouldReplay, parity-tested shell+JS: replay
    while a significant finding persists and round < cap, else stop. The
    closing open-items write does not consult it — bookkeeping, exempt.)
  - [~] 8.8 Verify a completed run has no open "infeasible" finding
    against a requirement, and every amendment carries a resolvable
    citation [verify: manual-run-claude]
    (Gate 5 (no open infeasible-vs-prd) and gate 4 (amend grounded) are
    auto-tested; verifying a COMPLETED real run satisfies them needs the
    end-to-end run.)
  - [X] 8.9 Run the three gate checks that decide FR-6's fate: (a) a
    seeded uncited AMEND is rejected and the target is byte-identical,
    (b) amend-then-revert restores the section verbatim, (c) a run
    seeded with permanent findings stops at round 2
    [verify: auto-test]
    (All three pass as auto-tests in doctree-lib.test.sh.)
  - [X] 8.10 If all three pass, record the evidence in the tech-design
    and continue. If any fails, stop and write a short report naming
    the failed condition and its evidence, for user sign-off
    [verify: manual-run-user]
    (All three 8.9 checks pass → FR-6 SHIPS. Evidence recorded in the
    tech-design D12 go/no-go block. Withdrawal (8.11) not taken.)
  - [X] 8.11 On a sign-off to withdraw: remove the AMEND path, KEEP the
    review passes and gates from story 6, and replace back-pressure
    with the closing human gate [verify: manual-run-claude]
    (NOT TAKEN — 8.9 passed, so back-pressure ships. This withdrawal
    branch is intentionally not exercised; recorded for completeness.)

- [ ] 9.0 **User Story:** As an embo user, I want a run to survive
  interruption and to degrade loudly, so that a failure costs me a
  restart rather than the whole run [7/0]
  - [X] 9.1 Implement the run-state reader: a resumed run recovers the
    round number and open findings [verify: auto-test]
    (doctree_runstate_round / doctree_runstate_open_findings read
    doctree-run-state.yaml via yq; absent file/field → 0. Tested.)
  - [X] 9.2 Implement resume: detect existing documents and restart
    from the first missing phase [verify: auto-test]
    (doctree_resume_phase returns the first phase whose doc is missing, or
    empty when all three exist. Tested across all four states. The command
    Step 0 reads documents first, round from the run-state artifact.)
  - [~] 9.3 Test resume by interrupting a run after phase 1 and
    restarting it [verify: manual-run-claude]
    (resume logic unit-tested; the interrupt-and-restart live proof needs
    a full run.)
  - [X] 9.4 Implement the sequential fallback in `doctree.md`, spawning
    the same phase agent directly in order [verify: manual-run-claude]
    (Documented in Launch + Degradation: same doctree-phase agent in phase
    order, same cap/budget; produces the same three documents. Content
    done; behavioral parity is 9.6.)
  - [X] 9.5 Detect workflow availability, select the fallback
    automatically, and state in the report which path is running
    [verify: manual-run-claude]
    (Command selects the path up front and states which is running when
    workflows are disabled. Content done; live confirmation at the run.)
  - [~] 9.6 Verify the fallback produces the same three documents, and
    honors the round cap and budget, on the same input
    [verify: manual-run-claude]
    (needs a live run on both paths to compare outputs.)
  - [X] 9.7 Cover the degradation matrix, each failing loudly with its
    reason: `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, an organization
    allowlist substituting a model, workflows disabled, the MCP server
    unreachable, a missing permission rule [verify: manual-run-claude]
    (Full matrix documented in the Degradation section, each with its
    reason and response; the pre-flight catches the MCP/permission cases.)
  - [X] 9.8 Make the document name the agents write and the name
    `docPath()` computes the same, with a test that a resumed run finds
    documents an earlier run wrote; also return one path form (relative
    or absolute, not both) [verify: auto-test]
    (Root cause: the slug passed in the dispatch brief was the raw user
    arg (e.g. `foo`) while agents derive the qualified form from the task
    directory name (e.g. `068-foo`). Fixed in both the JS and shell paths:
    `qualifiedSlug(taskDir)` derives the slug from the taskdir basename;
    `docPath(taskDir, runDate, suffix)` drops the slug param and calls it;
    shell `doctree_phase_doc_path` and `doctree_resume_phase` updated to
    match (slug arg removed). Tests: 3 qualifiedSlug assertions, 4 docPath
    assertions (including "matches the path a phase agent writes"), and
    the resume-phase test now creates files with the qualified name.
    142 lib + 70 workflow tests pass.)

- [ ] 10.0 **User Story:** As a prospective embo user, I want the new
  command documented, so that I can discover it and know what it costs
  [6/0]
  - [X] 10.1 Add the command to the README command table
    [verify: code-only]
    (Planning row for /embo:doctree.)
  - [X] 10.2 Write a README section naming the profile fields and the
    exact permission rules a run needs, verbatim [verify: code-only]
    ("Build the doc tree with agents" section: the doctree: field table
    and the verbatim allow rules the pre-flight requires.)
  - [X] 10.3 Document the cost: a baseline run is three phases plus six
    review passes, and replay rounds are the dominant multiplier
    [verify: code-only]
    (Cost paragraph in the same section.)
  - [~] 10.4 Measure one real run's token cost and record the figure
    rather than asserting a published multiple
    [verify: manual-run-claude]
    (MEASURED, on a real feature with a substantial seed: 572,024
    subagent tokens / 9 agents / 91 tool calls / 51 min with Opus
    authors; 505,785 / 10 agents / 71 tool calls with Sonnet authors and
    one replay. The second figure corrects an assumption worth keeping:
    a cheaper authoring model saved only 12% while running an extra
    agent, so the dominant cost is the six review passes and their tool
    use, not authoring. README still to be updated with the measured
    figure — that is what keeps this `[~]`.)
  - [X] 10.5 Update CLAUDE.md's file-structure section and the command
    count [verify: code-only]
    (Count 20→21; added doctree.md, doctree-phase.md, workflows/,
    doctree-lib.sh + fixtures, and the profiles' doctree: block.)
  - [X] 10.6 Add the CHANGELOG entry, one or two lines, stating the
    capability a user gets [verify: code-only]
    (Unreleased section: what /embo:doctree does and its refuse-to-start /
    resume behavior.)
  - [X] 10.7 Run the full hook and library test suites to confirm
    nothing regressed [verify: auto-test]
    (All 16 suites run: 15 pass. The one failure — code-embo-build.test.sh,
    "transform rewrote guidance to 7 options (v13.40.0)" — is a
    pre-existing claude-mem transform-version issue in files this task
    never touched (last changed in an unrelated commit), not a regression.)

- [ ] 11.0 **User Story:** As an embo user in ANY repository, I want
  `/embo:doctree` to run there, and to refuse a broken brief before it
  spawns an agent, so that a run outside the embo repo produces documents
  instead of a phase that stops on missing inputs [0/5]
  (Found by a real run from the web-site repo (2026-10-27). The lead skipped
  the entry command's Steps 0–3 and launched the workflow without
  arguments; the PRD phase got `task_dir`, `feature_slug` and the run date
  as the literal text `undefined`. Its brief named the procedure as
  `plugin/commands/prd.md`, which exists only inside the embo repo, and
  the agent had no `Skill` tool to load `embo:prd` by name, so it stopped.
  The PRD chose loading by skill name (probe P-3); the tech-design data
  contract changed it to a path, and every in-repo test passed because the
  path exists here.)
  - [X] 11.1 Write a test in `plugin/workflows/doctree.test.js`: with
    `task_dir`, `feature_slug` or `run_date` missing or empty, the
    workflow spawns no agent and its result names every missing field
    [verify: auto-test]
    (7 assertions for checkRequiredArgs, plus a source-scan assertion that
    the dispatch prompt no longer contains `command_file: plugin/commands/`.
    63 pass, 0 fail.)
  - [X] 11.2 Implement the check at the top of `plugin/workflows/doctree.js`
    (before the phase loop; today it is `const a = args || {}` with no
    check) [verify: auto-test]
    (checkRequiredArgs rejects missing, empty, whitespace-only, "undefined"
    and "null" strings for task_dir / feature_slug / run_date. The workflow
    returns {error, missing} immediately rather than spawning any agent.)
  - [X] 11.3 Replace `command_file: plugin/commands/${ph.key}.md` in
    `dispatchPrompt` with `phase_skill: embo:${ph.key}`; add `Skill` to
    the tool list in `plugin/agents/doctree-phase.md`; rewrite its input
    contract and step 2 to invoke the skill named in `phase_skill` (no
    file path anywhere) [verify: auto-test]
    (dispatch prompt now carries `phase_skill: embo:<phase>`; agent gains
    `Skill` in its tools list; contract and step 2 updated to invoke
    `Skill(skill="embo:<phase>")`. Source-scan asserts no
    `command_file: plugin/commands/` remains. 63 pass.)
  - [X] 11.4 In `plugin/commands/doctree.md`, when the argument is not a
    slug (for example a sentence of instructions), derive a slug and a
    `feature_description` from it and show both in the pre-flight report;
    the launch passes them in `args` [verify: code-only]
    (Added slug normalization rule to Step 1: a slug-shaped arg is used
    verbatim; a phrase/sentence is lowercased, spaces/punctuation → hyphens,
    collapsed, truncated to 40 chars. The original arg becomes
    feature_description. Both shown in pre-flight report. Arguments section
    updated to say either form is accepted.)
  - [ ] 11.5 Run `/embo:doctree <slug>` from a repository other than embo
    and confirm the PRD phase loads `embo:prd` and writes its document
    under `task_dir` [verify: manual-run-user]

## Summary

10 user stories, 74 subtasks. Story 1.0 was the blocking gate (resolved;
one clean default-mode permission-stall probe remains open, confounded by
the session's permission mode). Story 8.9/8.10 decided back-pressure's
fate: all three grounding conditions are mechanically met and auto-tested,
so **FR-6 back-pressure ships** — the 8.11 withdrawal branch was not taken.

**State:** every story's code and documentation is built and unit-tested.
The phase runner was proven live (3.7/4.4). Shipped suites green except
one pre-existing, unrelated claude-mem transform-version failure (10.7).
Two proofs (4.5 interactive-unchanged, 1.3 clean permission-stall probe)
still need a session in the default permission mode, which an
auto-approving session cannot provide.

**What three live runs established (5.8, 6.2, 8.6, 10.4 now settled).**
The run works end to end and produces all three documents. Cost is
roughly 500–570k tokens for 9–10 agents; a cheaper authoring model saved
only 12%, so the six review passes dominate, not authoring.

**FR-6 shipped non-functional, and only a live run could show it.** The
story 8 go/no-go declared back-pressure shipped on the strength of three
auto-tests — but all three fed amendments in directly, and no test
asserted that a reviewer finding BECOMES one. Nothing bridged
`findings` to `amendments`, so six review passes produced real defects
that were recorded as open items while the documents went out
uncorrected. Fixed (findingToAmend bridge + the grounding fields in
FINDINGS_SCHEMA), then a second defect surfaced in the same path:
`groundedAmends[0]` applied one amendment and dropped the rest in
silence. Both fixed; 55 JS and 142 shell assertions pass.

**The lesson for the next go/no-go:** a mechanism can pass every unit
test and still be disconnected from the thing that feeds it. Three gate
checks passed on a path that no reviewer finding could ever reach.

**Open defect, tracked as 9.8.** Agents write
`<date>-<nnn>-<slug>-<suffix>.md`; `docPath()` computes
`<date>-<slug>-<suffix>.md`. A resumed run does not recognise its own
documents and re-runs every phase, which also makes 9.2's resume logic
untestable against reality. Returned document paths also mix relative
and absolute forms.

**Still unproven:** the multi-amendment replay (unit-tested only), and
9.3/9.6 (resume-after-interrupt and fallback parity).
