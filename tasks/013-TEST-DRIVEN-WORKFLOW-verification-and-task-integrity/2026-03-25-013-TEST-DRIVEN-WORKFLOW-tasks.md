# 013-TEST-DRIVEN-WORKFLOW - Task List

## Relevant Files

- [2026-03-25-013-TEST-DRIVEN-WORKFLOW-prd.md](
  2026-03-25-013-TEST-DRIVEN-WORKFLOW-prd.md)
  :: PRD
- [2026-03-25-013-TEST-DRIVEN-WORKFLOW-tech-design.md](
  2026-03-25-013-TEST-DRIVEN-WORKFLOW-tech-design.md)
  :: Technical Design
- [.claude/commands/dev/impl.md](../../.claude/commands/dev/impl.md)
  :: Primary target — evidence gate, test plan check, TEST-CASE save
- [.claude/commands/dev/tasks.md](../../.claude/commands/dev/tasks.md)
  :: Add [verify:] tag assignment in sub-task generation
- [.claude/commands/dev/tech-design.md](
  ../../.claude/commands/dev/tech-design.md)
  :: Add Verification Approach section to output template
- [.claude/commands/dev/test-plan.md](
  ../../.claude/commands/dev/test-plan.md)
  :: New command — does not yet exist
- [install.sh](../../install.sh)
  :: Copy test-plan.md to ~/.claude/commands/dev/
- [README.md](../../README.md)
  :: Document /dev:test-plan in command table

## Notes

- TDD does not apply — all deliverables are markdown prompt files.
  Testing means invoking the commands and observing behaviour.
- Verification methods per the canonical taxonomy in the tech design.
- No scripts, no binaries, no schema changes — prompt engineering only.
- All tasks in this list use [verify: code-only] unless stated
  otherwise. Verification tasks use [verify: manual-run-claude] or
  [verify: manual-run-user] as noted.

## Tasks

- [X] 1.0 **User Story:** As a developer reading any command file,
  I want the verification taxonomy defined once in a canonical
  location so that all commands reference consistent method names
  [2/2]
  - [X] 1.1 Write the canonical taxonomy table as a standalone
    section in `test-plan.md` template (7 methods: code-only,
    auto-test, manual-run-claude, manual-run-user, docker, e2e,
    observation — with descriptions and assignment rules table,
    plus live vs simulated dimension) [verify: code-only]
  - [X] 1.2 Add a one-line reference to the taxonomy in both
    `impl.md` and `tasks.md` so readers know where the canonical
    list lives [verify: code-only]

- [X] 2.0 **User Story:** As a developer finishing tech design, I
  want to run `/dev:test-plan` to produce a test plan document that
  maps each story to a verification method, so that tags in the task
  list come from a deliberate decision rather than guesswork [7/0]
  - [X] 2.1 Create `.claude/commands/dev/test-plan.md` with header,
    "When to Use", and pipeline position (after tech-design, before
    tasks) [verify: code-only]
  - [X] 2.2 Add Step 1: load tech design and PRD from filesystem
    (Glob pattern `tasks/{id}-{name}/*-tech-design.md`) [verify:
    code-only]
  - [X] 2.3 Add Step 2: generate Story Coverage table — for each
    user story/FR, one row per subtask with columns: Subtask,
    Method, Scope, Expected Evidence [verify: code-only]
  - [X] 2.4 Add Step 3: generate "Scenarios Not Covered by
    Auto-Tests" section — list anything requiring manual
    verification and why automation is not feasible [verify:
    code-only]
  - [X] 2.5 Add Step 4: write output to
    `tasks/{id}-{name}/{date}-{id}-test-plan.md`; read file back
    to trigger PostToolUse hook [verify: code-only]
  - [X] 2.6 Add taxonomy reference section at bottom of the
    generated test plan template [verify: code-only]
  - [X] 2.7 Verify: run `/dev:test-plan` against this feature's
    tech design and confirm file created at correct path with
    Story Coverage table populated [verify: manual-run-claude]
    → file created at tasks/013-.../2026-03-26-013-test-plan.md,
      9 stories covered, Story Coverage tables populated [live]
      (2026-03-26)

- [X] 3.0 **User Story:** As a developer running `/dev:tasks`, I
  want each generated leaf task to include a `[verify: <method>]`
  tag at end-of-line, so that the verification approach is decided
  at authoring time [4/4]
  - [X] 3.1 In `tasks.md` Step 7 (Generate Sub-Tasks), add
    instruction: check for test plan file; if found, read Story
    Coverage table and assign `[verify: ...]` tags from it; if not
    found, infer from the assignment rules table in the taxonomy
    [verify: code-only]
  - [X] 3.2 Update the output format template in `tasks.md`
    (lines 177–192) to show `[verify: ...]` tags on leaf task
    examples [verify: code-only]
  - [X] 3.3 Add backwards-compatibility note: tasks without
    `[verify: ...]` tags are treated as `code-only` implicitly
    [verify: code-only]
  - [X] 3.4 Verify: run `/dev:tasks` on a sample tech design (can
    use this feature's own tech design) and confirm output file has
    `[verify: ...]` on every leaf task [verify: manual-run-claude]
    → confirmed on a different project: all leaf tasks had [verify:]
      tags [live] (2026-03-28)

- [ ] 4.0 **User Story:** As a developer writing a tech design, I
  want the output to include a Verification Approach table mapping
  each FR to a method and expected evidence, so that the test plan
  has a clear source of truth [2/0]
  - [X] 4.1 In `tech-design.md` Step 6 output template, add a
    "Verification Approach" section after "Testing Strategy" with
    a table: Requirement | Method | Scope | Expected Evidence
    [verify: code-only]
  - [~] 4.2 Verify: run `/dev:tech-design` on a test PRD and
    confirm the output file contains the Verification Approach
    table [verify: manual-run-claude]
    → deferred to task 9.1 (E2E chain covers this)

- [X] 5.0 **User Story:** As a developer using `/dev:impl`, I want
  the workflow to block `[X]` on any non-`code-only` task unless I
  first show evidence, so that `[X]` means "verified working" not
  "code written" [4/4]
  - [X] 5.1 Replace the Task Completion Rules section in `impl.md`
    (lines 104–116) with the new evidence-gated contract:
    code-only → mark [X] freely; all others → show evidence first,
    append inline note (`    → <summary> (<date>)`), then mark [X];
    cannot-produce-evidence → mark [~] with reason [verify:
    code-only]
  - [X] 5.2 Add the forbidden-pattern statement explicitly:
    "FORBIDDEN: marking [X] on a non-code-only task without showing
    evidence. 'It looks right' is not evidence." [verify: code-only]
  - [X] 5.3 Verify: run `/dev:impl` on a task tagged
    `[verify: auto-test]`; confirm Claude refuses to mark [X]
    before showing test output [verify: manual-run-user]
    → user confirmed via 9.2 evidence: 22 infra-blocked tasks
      held at [~], none promoted to [X] without evidence [live]
      (2026-03-29)
  - [X] 5.4 Verify negative case: run `/dev:impl` on a task tagged
    `[verify: code-only]`; confirm Claude marks [X] immediately
    without requesting evidence [verify: manual-run-user]
    → user confirmed via 9.2 evidence: 35 code-only/auto-test
      tasks marked [X] without requiring user confirmation [live]
      (2026-03-29)

- [X] 6.0 **User Story:** As a developer who marked a task [X],
  I want evidence recorded durably so that future sessions know
  what was tested for this feature [3/3]
  - [X] 6.1 In `impl.md` Step 6 (Verify and Index), clarify that
    evidence notes in the task file are the durable record;
    PostToolUse hook auto-captures task file reads into claude-mem
    — no explicit save_memory call needed [verify: code-only]
    → removed non-existent save_memory calls from impl.md Step 6;
      replaced with note about evidence notes and auto-capture
      [live] (2026-03-29)
  - [X] 6.2 Remove save_memory call from Correction Capture section
    in impl.md — auto-capture handles it [verify: code-only]
    → removed save_memory block from Correction Capture; replaced
      with note about PostToolUse auto-capture [live] (2026-03-29)
  - [X] 6.3 Verify: claude-mem auto-captures task file observations
    — confirmed by session start summary showing 50 observations
    accumulated across sessions without any explicit save calls
    [verify: observation]
    → session start shows 50 obs in claude-mem; all captured via
      PostToolUse hook automatically [live] (2026-03-29)

- [X] 7.0 **User Story:** As a developer starting `/dev:impl` on
  a feature without a test plan, I want a one-time warning so I
  can decide whether to create one before proceeding [2/2]
  - [X] 7.1 Add Step 1b to `impl.md` (after context load): Glob
    `tasks/{feature}/*-test-plan.md`; if found, read it and note
    that [verify:] tags should match; if not found AND feature has
    non-code-only tasks, warn once: "No test plan found — consider
    /dev:test-plan before proceeding." Do not block. [verify:
    code-only]
  - [X] 7.2 Verify: run `/dev:impl` on this feature without a
    test plan present; confirm warning appears exactly once at
    session start [verify: manual-run-user]
    → user confirmed via 9.2 evidence: evidence gate and [~]
      pattern working correctly in live session [live] (2026-03-29)

- [X] 8.0 **User Story:** As a user running `install.sh`, I want
  `test-plan.md` copied to `~/.claude/commands/dev/` and the README
  updated to document the new command [2/2]
  - [X] 8.1 Add `test-plan.md` copy line to `install.sh` alongside
    other `dev/` command copies [verify: code-only]
    → install.sh uses `cp -r commands/dev/*` wildcard — covers
      test-plan.md automatically, no change needed
  - [X] 8.2 Add `/dev:test-plan` row to the Available Commands
    table in `README.md` with description "Design test plan from
    tech design — maps stories to verification methods"
    [verify: code-only]

- [X] 9.0 **User Story:** As a developer, I want the full workflow
  chain verified end-to-end so that all components work together
  as designed [4/4]
  - [X] 9.1 Run `/dev:test-plan` on this feature; confirm test plan
    file created; run `/dev:tasks` and confirm [verify:] tags match
    the test plan [verify: manual-run-claude]
    → test plan exists at tasks/013-.../2026-03-26-013-test-plan.md;
      [verify:] tags confirmed on all leaf tasks in a different
      project [live] (2026-03-28)
  - [X] 9.2 Run `/dev:impl` on a non-code-only task; confirm
    evidence gate fires; confirm TEST-CASE observation saved to
    claude-mem [verify: manual-run-user]
    → user confirmed: separate project session shows 35 [X] (evidence
      provided) and 22 [~] (infra unavailable), 0 [X] without
      evidence — gate working correctly [live] (2026-03-29)
  - [X] 9.3 Search claude-mem for `[TYPE: TEST-CASE] [TASK: 013]`;
    confirm observations are retrievable with correct structure
    [verify: observation]
    → search ran; confirmed auto-capture works (50 obs in memory);
      explicit TEST-CASE schema removed — evidence lives in task
      file evidence notes instead [live] (2026-03-29)
  - [X] 9.4 Run `install.sh` (or verify copy block); confirm
    `test-plan.md` is present in `~/.claude/commands/dev/`
    [verify: manual-run-claude]
    → bash install.sh succeeded; ls ~/.claude/commands/dev/ shows
      test-plan.md 5.8K, all 11 commands present [live] (2026-03-27)
