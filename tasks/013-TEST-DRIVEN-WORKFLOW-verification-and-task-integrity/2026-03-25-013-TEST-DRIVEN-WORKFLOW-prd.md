# 013-TEST-DRIVEN-WORKFLOW: Verification-First Task Integrity - PRD

**Status**: Draft
**Created**: 2026-03-25
**Author**: Claude (via dev workflow analysis)
**Branch**: `feature/013-test-driven-workflow`

---

## Introduction / Overview

There is a well-known failure mode in AI-assisted development: Claude writes code,
marks tasks `[X]`, and declares them done — without running anything, without seeing
output, without evidence of any kind. The task list looks complete. The feature may
not work.

This failure compounds across three distinct gaps in the current RLM-Mem workflow:

1. **Completion without evidence** — `[X]` is marked after writing code, not after
   verifying it. There is no distinction between "code written" and "code working."

2. **Test design is an afterthought** — verification is thought about at completion
   time ("how do I prove this works?"), not at design time ("what would prove this
   works?"). By the time a task is implemented, the verification approach is often
   unclear.

3. **Test memory is ephemeral** — test cases and their outcomes exist only in the
   current session. There's no way to retrieve "what tests covered this feature" or
   "what scenarios were verified for task X" in a future session.

This PRD describes a workflow enhancement that addresses all three gaps:
- **Verification tags on tasks**, set at authoring time, enforced at completion
- **A test-plan document** as a first-class artifact between tech-design and tasks
- **Claude-mem tagging** for test cases, enabling cross-session retrieval by
  feature or task ID

The existing test subagents (`test-backend`, `test-e2e-*`, `test-review`) remain
**outside this workflow**. They are execution tools. This feature is about
*specifying what to test and proving it was tested* — not about how tests run.

---

## Objectives & Success Metrics

**Objectives:**
- Eliminate `[X]` being marked without evidence for testable tasks
- Make verification planning happen before implementation, not after
- Make test outcomes retrievable across sessions via claude-mem
- Preserve zero overhead for tasks where testing genuinely doesn't apply

**Success Metrics:**
- A verification task cannot be marked `[X]` in `impl.md` without
  inline evidence (command output, test result, observation reference)
- Test plans exist before implementation starts on any feature with
  functional requirements
- Running `/dev:tasks` produces tasks with `[verify: ...]` tags
- A session 3 months from now can retrieve "all test cases for task 013"
  from claude-mem

---

## User Personas & Use Cases

### Personas

**Developer using /dev:impl**: Implements tasks daily. Currently marks
`[X]` freely and may not realize they're doing it incorrectly. Needs
a clear contract: what must be shown before checking the box.

**Developer reviewing completed work**: Looks at a task list and sees
all `[X]`. Currently has no way to distinguish "tested" from "I wrote
it and it looks right." Needs inline evidence so verification is
auditable at a glance.

**Future session (any developer)**: Returns to a feature weeks later.
Currently cannot answer "what was tested?" without re-reading code.
Needs claude-mem to surface test cases by tag.

---

## User Stories

### Story 1 — Task authoring includes verification method

**As a** developer running `/dev:tasks`,
**I want** each generated task to include a `[verify: <method>]` tag,
**so that** the verification approach is decided at design time, not
guessed at completion time.

**Acceptance Criteria:**
- [ ] `/dev:tasks` generates tasks with `[verify: <method>]` tags
- [ ] Method is one of the canonical set (see FR-1)
- [ ] `[verify: code-only]` tasks require no evidence at completion
- [ ] `[verify: auto-test | manual-run-claude | manual-run-user |
  docker | e2e | observation]` tasks require inline evidence
- [ ] Tag is set based on the test plan (if exists) or tech-design
  guidance; Claude does not assign it arbitrarily

---

### Story 2 — Completion requires inline evidence for testable tasks

**As a** developer marking a task `[X]` in `/dev:impl`,
**I want** the workflow to require me to show evidence before checking off
any task tagged `[verify: *]` (except `code-only`),
**so that** `[X]` means "verified working," not "code written."

**Acceptance Criteria:**
- [ ] Before marking `[X]` on a non-`code-only` task, `impl.md`
  instructs Claude to show the specific evidence
- [ ] Evidence is appended inline in the task file, e.g.:
  `[X] 2.1 Add correction capture — [verified: auto-test, pytest
  output: 3 passed, 0 failed, 2026-03-25]`
- [ ] If Claude cannot produce evidence (e.g., can't run the test),
  it marks `[~]` (coded, pending) and states why
- [ ] `[X]` without evidence on a testable task is explicitly
  forbidden in the workflow instructions

---

### Story 3 — Test plan as a first-class document

**As a** developer running `/dev:tech-design`,
**I want** the workflow to produce (or prompt for) a test plan document
alongside the technical design,
**so that** what needs testing is decided before any implementation starts.

**Acceptance Criteria:**
- [ ] `/dev:tech-design` includes a step that generates a test plan
  section (or separate file) covering: what to test, verification
  method per story/requirement, and expected outcomes
- [ ] Test plan is referenced by `/dev:tasks` when assigning
  `[verify: ...]` tags — tags come from the plan, not ad hoc
- [ ] Test plan document persists at
  `tasks/{id}-{name}/{date}-{id}-test-plan.md`
- [ ] If no test plan exists when `/dev:impl` starts, the workflow
  warns and offers to create one before proceeding

---

### Story 4 — Test cases tagged in claude-mem

**As a** developer returning to a feature in a future session,
**I want** to retrieve "what test cases were defined and verified for
task 013" from claude-mem,
**so that** I don't have to re-read the codebase to understand what
was tested.

**Acceptance Criteria:**
- [ ] When a task with a test plan is implemented and verified, the
  test case(s) and outcome(s) are saved to claude-mem with tags:
  `[TYPE: TEST-CASE]`, `[TASK: <id>]`, `[STATUS: passed|failed|skipped]`
- [ ] A search for `[TYPE: TEST-CASE] [TASK: 013]` returns all test
  cases for feature 013
- [ ] Observations include: what was tested, how, outcome, date

---

### Story 5 — Tech-design drives test scope (upstream authoring quality)

**As a** developer writing a tech design,
**I want** the tech design template to include a "Verification Approach"
section per component or user story,
**so that** test planning is informed by design decisions, not reverse-engineered
from implementation.

**Acceptance Criteria:**
- [ ] `/dev:tech-design` template includes a "Verification Approach"
  section that maps each functional requirement to: method, scope
  (unit / integration / e2e / manual), and expected evidence
- [ ] This section becomes the primary input to the test plan document
- [ ] Existing tech designs without this section are not invalidated —
  new section is additive

---

## Requirements

### Functional Requirements

**FR-1: Canonical verification method taxonomy**
- **Methods**:
  - `code-only` — no runtime test possible or needed (docs, config text, prompt files)
  - `auto-test` — automated test suite run (pytest, jest, go test, etc.)
  - `manual-run-claude` — Claude executes a command and shows output
  - `manual-run-user` — user runs something and reports result
  - `docker` — verified inside Docker container (integration/environment test)
  - `e2e` — end-to-end via test subagents (Playwright etc.)
  - `observation` — evidence is a claude-mem observation or search result
- **Priority**: Critical — this taxonomy is used everywhere else

**FR-2: `[verify: <method>]` tag in task format**
- Tasks generated by `/dev:tasks` include the tag on each leaf task
- Tag is set from test plan if available; otherwise inferred from
  tech-design or task type
- `tasks.md` command updated to include this step
- **Priority**: Critical

**FR-3: Inline evidence requirement in `impl.md`**
- Before marking `[X]` on a non-`code-only` task, `impl.md` requires
  showing the evidence and appending a short inline note to the task entry
- Inline note format: `[verified: <method>, <evidence-summary>, <date>]`
- If evidence unavailable, mark `[~]` with reason
- **Priority**: Critical

**FR-4: Test plan document (`/dev:tech-design` or new `/dev:test-plan`)**
- Option A: Add "Verification Approach" section to `tech-design.md` output,
  then extract to a separate test plan file via a new step
- Option B: New `/dev:test-plan` command that reads tech-design and
  generates the plan document as a standalone step
- **Decision**: Option B — keeps tech-design focused on architecture,
  test plan is its own artifact. Test plan is optional for `code-only`
  features, required for anything with functional requirements.
- **Priority**: High

**FR-5: Claude-mem test case observations**
- When a verified task is marked `[X]`, save a `[TYPE: TEST-CASE]`
  observation to claude-mem
- Tags: `[TYPE: TEST-CASE]`, `[TASK: <id>]`, `[STATUS: passed|failed|skipped]`
- Content: what was tested, method, outcome summary, date
- **Priority**: High

**FR-6: `impl.md` warning if no test plan**
- At the start of `/dev:impl`, check if a test plan file exists for
  the active task set
- If not: warn and offer to run `/dev:test-plan` before proceeding
- Do not hard-block (user can override), but make the gap visible
- **Priority**: Medium

### Non-Functional Requirements

**NFR-1: Zero overhead for `code-only` tasks** — Docs, config, and prompt
file changes must flow through unchanged. No evidence required, no friction added.

**NFR-2: Evidence is brief** — The inline note is a one-liner, not a test
report. The point is traceability, not verbosity.

**NFR-3: No test subagent coupling** — This feature does not depend on or
modify the test subagents (`test-backend`, `test-e2e-*`, `test-review`).
They remain independent execution tools. The workflow specifies *what* to test;
subagents are one *way* to test it.

**NFR-4: Backwards compatible** — Existing tasks without `[verify: ...]` tags
are treated as `code-only` (no evidence required). Old task files don't break.

### Technical Constraints

- All changes are to `.md` command prompt files — no new scripts or binaries
- Claude-mem test case observations use existing PostToolUse hook pattern
- Test plan document follows same file naming convention as PRD/tech-design
- `[verify: ...]` tag is plain text appended to task line — no schema changes

---

## Out of Scope

- **Modifying test subagents** — they remain unchanged and separate
- **Automated test execution from within workflow commands** — commands
  instruct Claude to run tests; they don't orchestrate subagents automatically
- **Retroactive tagging of existing tasks** — existing `[ ]` tasks are
  treated as `code-only` unless manually updated
- **Test coverage metrics** — no automated measurement of coverage ratios
- **Shared `_commons.md`** — DRY extraction of shared rules across commands
  remains deferred (per prior decision)

---

## Gherkin Scenarios

```gherkin
Feature: Verification-First Task Integrity

  Scenario: Task generated with verify tag
    Given a tech-design and test plan exist for feature 013
    When the developer runs /dev:tasks
    Then each leaf task includes a [verify: <method>] tag
    And tasks with functional behavior are tagged [verify: auto-test]
      or [verify: manual-run-claude] etc.
    And tasks that only change docs/prompts/config are tagged
      [verify: code-only]

  Scenario: Cannot mark [X] without evidence on a testable task
    Given a task is tagged [verify: auto-test]
    And the developer has implemented the code
    When the developer is about to mark the task [X]
    Then impl.md requires showing test output first
    And the inline note is appended: [verified: auto-test, 3 passed, 2026-03-25]
    And then [X] is marked

  Scenario: code-only task marked freely
    Given a task is tagged [verify: code-only]
    When the developer completes the change
    Then [X] can be marked immediately, no evidence required

  Scenario: Evidence unavailable — mark pending
    Given a task is tagged [verify: docker]
    And Docker is not running in the current session
    When the developer cannot run the test
    Then the task is marked [~] with note "docker not available in session"
    And [X] is NOT marked

  Scenario: Test case saved to claude-mem
    Given a task tagged [verify: auto-test] was completed with evidence
    When [X] is marked
    Then a [TYPE: TEST-CASE] observation is saved to claude-mem
    And it includes [TASK: 013-2.1], method, outcome, and date
    And a future session can retrieve it via search("[TYPE: TEST-CASE] [TASK: 013]")

  Scenario: No test plan — impl warns
    Given no test plan file exists for the active task set
    When the developer starts /dev:impl
    Then a warning is shown: "No test plan found for this feature"
    And /dev:test-plan is suggested
    And the developer can proceed without it (warning only, not a hard block)

  Scenario: Test plan drives verify tags
    Given a test plan specifies Story 1 should be verified via auto-test
    When /dev:tasks generates tasks for Story 1
    Then all non-trivial subtasks are tagged [verify: auto-test]
    Not [verify: code-only]
```

---

## References

### From Codebase

- `.claude/commands/dev/impl.md` — primary target: evidence requirement,
  test-case observation saving
- `.claude/commands/dev/tasks.md` — add `[verify: ...]` tag generation step
- `.claude/commands/dev/tech-design.md` — add "Verification Approach" section
- New: `.claude/commands/dev/test-plan.md` — new command
- `tasks/009-FEEDBACK-LOOP-*` — prior art for how corrections are structured
  and saved to claude-mem; similar pattern for test-case observations

### From Brainstorm (2026-03-25)

- User: "It's better to have overhead than the illusion of a completed task"
- User: explicit tag in task definition so verification method is decided
  at authoring time, not guessed at completion
- User: tech-design should define the testing approach at the top level
- User: separate test design document, maintained independently — TDD deserves
  a first-class place in the workflow
- User: claude-mem tagging for test cases, retrievable by feature/task ID
- User: test agents remain outside the workflow (execution tools, not spec tools)
- Behavioral rule captured: never mark `[X]` without evidence; show the specific
  command output or test result that proves it passed

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/dev:tech-design` to design the new command and modified commands
3. Run `/dev:tasks` to break down into implementation tasks
