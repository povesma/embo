# Generate Test Plan from Technical Design

Create a test plan document that maps each user story and functional
requirement to a verification method, scope, and expected evidence.
The test plan is the authoritative source for `[verify: ...]` tags
in the task list.

## When to Use

- After `/dev:tech-design` is approved
- Before running `/dev:tasks` (so tags come from the plan, not guesswork)
- When revisiting test coverage after scope changes

## Pipeline Position

```
/dev:prd → /dev:tech-design → /dev:test-plan → /dev:tasks → /dev:impl
```

This step is **optional but strongly recommended** for any feature with
functional requirements. Skip only for `code-only` features (docs,
config, prompt file changes with no runtime behaviour).

## Process

### Step 1: Load Tech Design and PRD

```bash
# Find tech design
ls tasks/{id}-{name}/
```

Read:
- Tech design: `tasks/{id}-{name}/*-tech-design.md`
  Focus on: Verification Approach table, Functional Requirements,
  Components
- PRD: `tasks/{id}-{name}/*-prd.md`
  Focus on: User Stories and Acceptance Criteria

If neither exists, stop and suggest running `/dev:tech-design` first.

### Step 2: Generate Story Coverage Table

For each user story in the PRD, produce a coverage table.

Per subtask/acceptance criterion, decide:
- **Method**: from the taxonomy below (default to `auto-test` for
  logic, `code-only` for docs/config)
- **Scope**: `unit` | `integration` | `e2e` | `manual`
- **Expected evidence**: what a passing result looks like
  (e.g., "pytest: N passed", "command output shows X", "user confirms Y")

Prefer the Verification Approach table from tech-design as input.
If it exists, use it directly. If not, infer from the story's
acceptance criteria.

### Step 3: Identify Intentional Gaps

List any acceptance criteria or behaviours that are **not** covered
by automated tests, and explain why:
- Not feasible to automate (e.g., requires live user interaction)
- Covered by a higher-level test that subsumes it
- Deferred to manual QA

This section is the honest record of what the test plan does not cover.

### Step 4: Write Output File

Save to: `tasks/{id}-{name}/{date}-{id}-test-plan.md`

After writing, **Read the file back** — the PostToolUse hook captures
it as a claude-mem observation automatically.

### Step 5: Report

```
✅ Test plan created: {path}

Stories covered: {N}
Subtasks mapped: {M}
  auto-test: {count}
  manual-run-claude: {count}
  manual-run-user: {count}
  code-only: {count}
  other: {count}

Intentional gaps: {K}

Next step: /dev:tasks  (will read this plan for [verify:] tags)
```

## Output Format

```markdown
# {id}: {Feature Name} — Test Plan

**Status**: Draft
**Tech Design**: [{id}-tech-design.md](link)
**Created**: {date}

## Story Coverage

### Story 1 — {title}

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 1.1 {description} | auto-test | unit | pytest: N passed |
| 1.2 {description} | code-only | — | — |
| 1.3 {description} | manual-run-claude | integration | output shows X |

### Story 2 — {title}

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 2.1 ... | ... | ... | ... |

## Intentional Gaps

- **{criterion}**: not automated because {reason}

## Verification Method Taxonomy

(canonical reference — do not modify here, edit `/dev:test-plan`)

| Method | When to use |
|--------|-------------|
| `code-only` | No runtime test possible or needed: docs, config,
  `.md` prompt files, YAML, plain text |
| `auto-test` | An automated test suite can verify this: pytest,
  jest, go test, cargo test, phpunit |
| `manual-run-claude` | Claude executes a command and captures the
  output as evidence |
| `manual-run-user` | User runs a command or action and reports
  the result to Claude |
| `docker` | Verification requires a Docker container environment
  (integration or environment test) |
| `e2e` | End-to-end test via Playwright or test subagents |
| `observation` | Evidence is a claude-mem observation or search
  result (e.g. verifying a save occurred) |

### Live vs Simulated

Every non-`code-only` verification must record whether it was live
or simulated in the evidence note:

- **`live`** — the actual system was exercised: real command run,
  real output, real side-effect observed. Default expectation.
- **`simulated`** — a mock, stub, or dry-run was used instead of
  the real system. Acceptable only when live testing is costly,
  destructive, or impossible. Must be stated explicitly.

Evidence note format (appended to task line on completion):
    → <summary> [live] (<date>)
    → <summary> [simulated: <reason>] (<date>)

Examples:
    → pytest: 3 passed, 0 failed [live] (2026-03-25)
    → docker not available, logic verified via unit mock
      [simulated: no Docker in session] (2026-03-25)

**At least one live test must be done before `[X]` is marked.**
If the first pass was simulated, a follow-up live test is required
before closing the task.
```

## Assignment Rules (when no test plan exists)

When `/dev:tasks` generates tasks without a test plan, infer method
from the task's nature:

| Task characteristics | Assign |
|----------------------|--------|
| Only modifies `.md`, `.yaml`, `.txt`, config | `code-only` |
| Adds/changes Python / JS / TS / Go logic | `auto-test` |
| Verifies a CLI command or script output | `manual-run-claude` |
| Requires Docker environment | `docker` |
| Tests UI or browser behaviour | `e2e` |
| Verifies a past memory or decision | `observation` |
| User must confirm something works | `manual-run-user` |

## Final Instructions

1. Read tech design and PRD
2. Generate Story Coverage table per story
3. List intentional gaps honestly
4. Write output file and read it back
5. Report summary and suggest `/dev:tasks`
6. DO NOT start generating tasks — wait for user
