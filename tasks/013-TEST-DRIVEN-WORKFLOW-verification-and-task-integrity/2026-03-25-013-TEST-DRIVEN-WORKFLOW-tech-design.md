# 013-TEST-DRIVEN-WORKFLOW: Verification-First Task Integrity — Technical Design

**Status**: Draft
**PRD**: [2026-03-25-013-TEST-DRIVEN-WORKFLOW-prd.md](2026-03-25-013-TEST-DRIVEN-WORKFLOW-prd.md)
**Created**: 2026-03-25

---

## Overview

All changes are to `.md` command prompt files. No scripts, no binaries,
no schema changes. The implementation is entirely prompt engineering:
adding behavioural rules and format constraints to four existing commands
and creating one new command.

The system introduces a **verification contract** with three enforcement
points:

1. **Authoring time** (`tasks.md`) — every leaf task gets a
   `[verify: <method>]` tag. Method is derived from the test plan if
   present, otherwise inferred from the task's nature.
2. **Completion time** (`impl.md`) — before marking `[X]`, Claude must
   show evidence and append an inline note. `code-only` tasks are exempt.
3. **Memory time** (`impl.md`) — after marking `[X]` on a testable task,
   save a `[TYPE: TEST-CASE]` observation to claude-mem.

A new `/dev:test-plan` command sits between `tech-design` and `tasks` as
an optional but recommended step. When it exists, it is the authoritative
source for `[verify: ...]` tags. When it doesn't, `tasks.md` infers.

---

## Current Architecture

This repo has no runtime code — it is a collection of `.md` prompt files
installed to `~/.claude/`. The "architecture" is the **command pipeline**:

```
/dev:prd → /dev:tech-design → [NEW: /dev:test-plan] → /dev:tasks → /dev:impl
```

Each command is a standalone Markdown file read by Claude Code as a slash
command. Commands share no runtime state — they communicate through the
file system (task files, test plan files) and claude-mem observations.

**Relevant existing components:**

- `impl.md` (11.0K) — Task Completion Rules section (`line 104–116`) is
  the primary target. Correction Capture section (`line 72–99`) is the
  pattern to follow for TEST-CASE observations.
- `tasks.md` (8.0K) — Phase 2 sub-task generation (Step 7) is where
  `[verify: ...]` tags are added. Output format template (`line 129–192`)
  defines the task line structure.
- `tech-design.md` (8.7K) — Step 6 synthesises the design document.
  A "Verification Approach" section is added to the output template.
- `test-plan.md` — does not yet exist. New file.

---

## Component Designs

### 1. Verification Taxonomy (shared contract)

The canonical taxonomy is defined once in `test-plan.md` and referenced
by name in `tasks.md` and `impl.md`. No duplication — each file refers to
"the canonical taxonomy" rather than reprinting it.

```
code-only        — no runtime test possible or needed
                   (docs, config text, .md prompt files)
auto-test        — automated test suite (pytest, jest, go test, ...)
manual-run-claude — Claude executes a command and captures output
manual-run-user  — user runs the command; reports result to Claude
docker           — verified inside Docker container
e2e              — end-to-end via Playwright test subagents
observation      — evidence is a claude-mem observation/search result
```

**Assignment rules** (for `tasks.md` inference when no test plan exists):

| Task characteristics | Default method |
|----------------------|---------------|
| Only modifies `.md`, `.yaml`, `.txt`, config | `code-only` |
| Adds/changes Python/JS/TS/Go logic | `auto-test` |
| Verifies a CLI command or script works | `manual-run-claude` |
| Requires Docker environment | `docker` |
| Tests UI or browser behaviour | `e2e` |
| Verifies a past memory or decision | `observation` |
| User must confirm something works | `manual-run-user` |

---

### 2. Task Line Format Changes (`tasks.md`)

**Current format** (line 177–190):
```markdown
- [ ] 1.1 Write tests for [specific functionality A] external interface
```

**New format:**
```markdown
- [ ] 1.1 Write tests for [specific functionality A] [verify: auto-test]
```

Tag placement: end of line, before any trailing punctuation.
Tag is on **leaf tasks only** — parent story lines (`1.0`, `2.0`) do not
get tags; they inherit status from children.

**Evidence note format** (appended on completion, indent 4 spaces):
```markdown
- [X] 1.1 Write tests for [specific functionality A] [verify: auto-test]
    → pytest: 3 passed, 0 failed (2026-03-25)
```

For `manual-run-user`, Claude writes the note after the user reports:
```markdown
- [X] 2.3 Verify profile activates correctly [verify: manual-run-user]
    → user confirmed: profile switched, statusline updated (2026-03-25)
```

For `code-only`, no evidence note — just `[X]`:
```markdown
- [X] 3.1 Add taxonomy to test-plan.md template [verify: code-only]
```

---

### 3. `impl.md` — Task Completion Rule Changes

**Target section**: "Task Completion Rules" (`line 104–116`).

**New contract** replacing the existing bullet points:

```
- [X] (done):
    - For [verify: code-only]: mark [X] immediately after completing the change.
    - For all other [verify: *]: MANDATORY — show evidence first, then append
      the inline note (→ <summary> (<date>)), then mark [X].
    - Explicitly confirmed by user overrides all of the above.
- [~] (coded, pending): implementation written but evidence not yet obtainable
    (e.g., docker not running, CI-only test). State the reason inline.
- [ ] (not started): no work done.
- FORBIDDEN: marking [X] on a non-code-only task without showing evidence.
  "It looks right" is not evidence. "I wrote it" is not evidence.
```

**New Step: Test Plan Check (added as Step 1b, after context load)**

Before starting any task session:
```
Check for test plan: Glob tasks/{feature}/*-test-plan.md
- If found: read it. [verify: ...] tags in the task list should match.
  Flag mismatches before implementing.
- If not found AND feature has non-code-only tasks: warn once —
  "No test plan found. Consider /dev:test-plan before proceeding."
  Do NOT block. User can proceed.
```

**Test-case observation save (added to Step 6)**

After marking `[X]` on any non-`code-only` task, save to claude-mem:

```
save_memory(
  title="Test: {task_id} — {task_description}",
  text="[TYPE: TEST-CASE]\n[TASK: {feature_id}-{task_num}]\n[STATUS: passed]\n[METHOD: {verify_method}]\n\n**What was tested**: {description}\n**Evidence**: {evidence_summary}\n**Date**: {date}"
)
```

Do NOT announce the save. Same silent pattern as correction capture.

For `[~]` (pending) tasks, save with `[STATUS: pending]` and include
the reason evidence was not obtainable.

---

### 4. New Command: `/dev:test-plan`

**File**: `.claude/commands/dev/test-plan.md`
**Position in pipeline**: optional step after `tech-design`, before `tasks`

**Inputs** (read from filesystem):
- Tech design file: `tasks/{id}-{name}/*-tech-design.md`
- PRD file (for user stories and acceptance criteria)

**Output**:
- `tasks/{id}-{name}/{date}-{id}-test-plan.md`

**Document structure** the command produces:

```markdown
# {id}: {Feature Name} — Test Plan

**Status**: Draft
**Tech Design**: [link]
**Created**: {date}

## Verification Approach

For each user story / functional requirement, define:
- What to test (behaviour, not implementation)
- Method (from canonical taxonomy)
- Scope (unit | integration | e2e | manual)
- Expected evidence (what "passing" looks like)

## Story Coverage

### Story 1 — {title}
| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 1.1 ... | auto-test | unit | pytest: N passed |
| 1.2 ... | code-only | — | — |

### Story 2 — {title}
...

## Scenarios Not Covered by Auto-Tests

List anything that requires manual verification and why automated
testing is not feasible. This is the authoritative record of
intentional gaps.

## Test Taxonomy Reference

code-only | auto-test | manual-run-claude | manual-run-user
| docker | e2e | observation
```

**How `tasks.md` consumes the test plan:**

When generating subtasks (Step 7), `tasks.md` checks for a test plan:
- If found: read the Story Coverage table. Assign `[verify: ...]` tags
  from the table, matching by story/subtask description.
- If not found: infer from the assignment rules table (see §1 above).

---

### 5. `tech-design.md` — Verification Approach Section

A new section added to the output template (Step 6), after "Testing
Strategy" and before "Trade-offs":

```markdown
## Verification Approach

Maps each functional requirement to its verification method and
expected evidence. This section drives the test plan.

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: ... | auto-test | unit | pytest: N passed |
| FR-2: ... | manual-run-claude | integration | command output shows X |
| FR-3: ... | code-only | — | — |
```

This section is **not** the test plan itself — it is architectural
guidance. `/dev:test-plan` reads it and expands it per story/subtask.

---

## Data Contracts

### Test-case claude-mem observation schema

```
title:  "Test: {feature_id}-{task_num} — {task_description}"
text:
  [TYPE: TEST-CASE]
  [TASK: {feature_id}-{task_num}]
  [STATUS: passed | failed | pending]
  [METHOD: code-only | auto-test | manual-run-claude | ...]

  **What was tested**: {one-line description of behaviour}
  **Evidence**: {evidence summary — e.g. "pytest: 3 passed, 0 failed"}
  **Date**: {YYYY-MM-DD}
```

Searchable by:
- `[TYPE: TEST-CASE]` — all test cases across all features
- `[TASK: 013]` — all tests for feature 013
- `[STATUS: pending]` — tests waiting for evidence
- `[METHOD: docker]` — tests that require Docker

### Task line schema

```
leaf task:  - [status] {num} {description} [verify: {method}]
evidence:       → {summary} ({date})       ← 4-space indent, arrow
parent task: - [status] {num} **User Story**: ...   ← no verify tag
```

---

## Sequence: Task Completion Flow

```
impl.md receives next task
       │
       ▼
read [verify: method] from task line
       │
       ├─ code-only ──────────────────────► mark [X], done
       │
       ├─ auto-test ──► run tests ─── pass ► append note ► mark [X]
       │                           └── fail ► mark [~] + reason
       │
       ├─ manual-run-claude ──► run cmd ──► capture output
       │                               ► append note ► mark [X]
       │
       ├─ manual-run-user ──► ask user for result
       │                    ► user confirms ► append note ► mark [X]
       │
       ├─ docker ──► docker available? ── yes ► run ► append note ► [X]
       │                              └── no  ► mark [~] + "docker n/a"
       │
       └─ e2e / observation ──► (similar pattern)
              │
              ▼
       save [TYPE: TEST-CASE] to claude-mem (silent)
```

---

## Trade-offs

### Tag placement: end-of-line vs. prefix

**Chosen**: end-of-line `- [ ] 1.1 Description [verify: auto-test]`

**Rejected**: prefix `- [ ] 1.1 [auto-test] Description`

**Rationale**: The description is the primary content; the tag is
metadata. End-of-line preserves readability of existing task lists and
is backwards-compatible — old lines without tags parse as `code-only`
without any tooling change.

### Evidence placement: same-line note vs. separate line

**Chosen**: indented sub-line `    → evidence (date)`

**Rejected**: same-line append

**Rationale**: Evidence lines can be longer than one-liners (e.g.,
multi-line test output summaries). Indented sub-line keeps the task
checkbox line clean and scannable while allowing multi-line evidence
when needed. The `→` prefix makes evidence lines visually distinct from
task lines in any markdown renderer.

### Test plan: standalone command vs. tech-design step

**Chosen**: standalone `/dev:test-plan`

**Rejected**: step inside `tech-design.md`

**Rationale**: Tech design answers "what to build and how." Test plan
answers "how do we know it works." These are different concerns with
different audiences and different update cycles. A test plan may be
revised during implementation; a tech design typically isn't. Keeping
them separate also preserves the optional nature of the test plan —
features that are `code-only` throughout don't need one.

### Backwards compatibility: old tasks without tags

**Decision**: tasks without `[verify: ...]` are treated as `code-only`
implicitly. No tooling change, no migration. The rule is stated in
`impl.md` so Claude knows to apply it.

---

## Files to Create/Modify

**Create:**
- `.claude/commands/dev/test-plan.md` — new command (~150 lines)

**Modify:**
- `.claude/commands/dev/impl.md`
  - Task Completion Rules section (`line 104–116`): replace with new
    evidence-gated contract
  - Add Step 1b: test plan check after context load
  - Step 6 (Verify and Index): add TEST-CASE observation save
- `.claude/commands/dev/tasks.md`
  - Step 7 (Generate Sub-Tasks): add `[verify: ...]` tag assignment
    step (from test plan or inferred)
  - Output format template (`line 176–192`): update example lines
    to show tags
- `.claude/commands/dev/tech-design.md`
  - Step 6 output template: add "Verification Approach" section
    after "Testing Strategy"

**No changes to:**
- Test subagents (`test-backend`, `test-e2e-*`, `test-review`)
- `rlm_repl.py`
- `install.sh`
- Any agent `.md` files

---

## Implementation Constraints

- All edits are to `.md` files read as prompts — no parsing, no
  validation, no CI. Correctness is enforced by Claude following the
  instructions, not by code.
- Evidence format must be human-readable in any markdown viewer without
  special tooling.
- `[verify: ...]` tags must not break existing markdown rendering —
  square brackets in list items render as literal text (not checkboxes)
  in standard markdown.
- claude-mem `save_memory` calls follow the same silent pattern as
  correction capture — no announcement, no flow interruption.

---

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: Taxonomy defined | code-only | — | — |
| FR-2: `[verify:]` tag in tasks output | manual-run-claude | integration | run `/dev:tasks` on a sample tech design, inspect output file |
| FR-3: Evidence gate in impl | manual-run-user | integration | run `/dev:impl` on a non-code-only task, confirm Claude blocks [X] without evidence |
| FR-4: test-plan command exists and runs | manual-run-claude | integration | run `/dev:test-plan`, confirm file created at correct path |
| FR-5: TEST-CASE saved to claude-mem | observation | integration | after marking [X], search claude-mem for `[TYPE: TEST-CASE] [TASK: 013]` |
| FR-6: impl warns on missing test plan | manual-run-claude | integration | run `/dev:impl` without test plan, confirm warning shown |

---

**Next Steps:**
1. Review and approve this design
2. Run `/dev:tasks` to break down into implementation tasks
