# 013-TEST-DRIVEN-WORKFLOW: Verification-First Task Integrity — Test Plan

**Status**: Draft
**Tech Design**: [2026-03-25-013-TEST-DRIVEN-WORKFLOW-tech-design.md](
  2026-03-25-013-TEST-DRIVEN-WORKFLOW-tech-design.md)
**Created**: 2026-03-26

---

## Story Coverage

### Story 1 — Task authoring includes verification method

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 1.1 Taxonomy table in test-plan.md | `code-only` | — | — |
| 1.2 Taxonomy reference in impl.md + tasks.md | `code-only` | — | — |

### Story 2 — Create /dev:test-plan command

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 2.1 File created with header + pipeline | `code-only` | — | — |
| 2.2 Step 1: load tech design + PRD | `code-only` | — | — |
| 2.3 Step 2: Story Coverage table | `code-only` | — | — |
| 2.4 Step 3: Intentional Gaps section | `code-only` | — | — |
| 2.5 Step 4: write output file | `code-only` | — | — |
| 2.6 Taxonomy reference at bottom | `code-only` | — | — |
| 2.7 Live verification: run /dev:test-plan | `manual-run-claude` | integration | test plan file created at correct path with Story Coverage table |

### Story 3 — [verify:] tags in /dev:tasks output

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 3.1 Instruction added to tasks.md Step 7 | `code-only` | — | — |
| 3.2 Output format template updated | `code-only` | — | — |
| 3.3 Backwards-compatibility note added | `code-only` | — | — |
| 3.4 Live verification: run /dev:tasks | `manual-run-claude` | integration | output file has [verify:] on every leaf task |

### Story 4 — Verification Approach in /dev:tech-design

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 4.1 Section added to tech-design.md template | `code-only` | — | — |
| 4.2 Live verification: run /dev:tech-design | `manual-run-claude` | integration | output contains Verification Approach table |

### Story 5 — Evidence gate in /dev:impl

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 5.1 Task Completion Rules replaced | `code-only` | — | — |
| 5.2 FORBIDDEN statement added | `code-only` | — | — |
| 5.3 Positive gate: [X] blocked without evidence | `manual-run-user` | integration | user confirms Claude refuses [X] on auto-test task without output |
| 5.4 Negative case: code-only marked freely | `manual-run-user` | integration | user confirms Claude marks [X] without requesting evidence |

### Story 6 — TEST-CASE claude-mem observation saving

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 6.1 Observation save instruction in impl.md | `code-only` | — | — |
| 6.2 [~] pending case handled | `code-only` | — | — |
| 6.3 Live verify: observation retrievable | `observation` | integration | search `[TYPE: TEST-CASE] [TASK: 013]` returns observation with correct fields |

### Story 7 — Missing test plan warning in /dev:impl

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 7.1 Step 1b added to impl.md | `code-only` | — | — |
| 7.2 Live verify: warning appears once | `manual-run-user` | integration | user confirms single warning shown at session start without test plan |

### Story 8 — install.sh + README

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 8.1 test-plan.md copy line in install.sh | `code-only` | — | — |
| 8.2 /dev:test-plan row in README | `code-only` | — | — |

### Story 9 — End-to-end verification

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 9.1 test-plan → tasks chain verified | `manual-run-claude` | e2e | [verify:] tags in tasks match test plan methods |
| 9.2 impl evidence gate + observation save | `manual-run-user` | e2e | user confirms gate fires + observation saved |
| 9.3 claude-mem retrieval | `observation` | e2e | search returns TEST-CASE observations for 013 |
| 9.4 install.sh copies test-plan.md | `manual-run-claude` | integration | file present at ~/.claude/commands/dev/test-plan.md |

---

## Intentional Gaps

- **Automated regression tests for command behaviour**: The commands
  are `.md` prompt files interpreted by an LLM — there is no
  deterministic test runner that can assert Claude follows the
  instructions. All verification is manual or observational.
- **Story 5.3 / 5.4 automated**: Cannot automate the test that Claude
  blocks or allows `[X]` without a human in the loop to observe the
  LLM session. Requires `manual-run-user`.
- **Story 7.2 automated**: Same reason — requires a live `/dev:impl`
  session observed by the user.

---

## Verification Method Taxonomy

(canonical reference — see `/dev:test-plan` for full definition)

| Method | When to use |
|--------|-------------|
| `code-only` | No runtime test possible or needed |
| `auto-test` | Automated test suite |
| `manual-run-claude` | Claude runs command, captures output |
| `manual-run-user` | User runs and reports result |
| `docker` | Requires Docker environment |
| `e2e` | End-to-end via Playwright/subagents |
| `observation` | Evidence is a claude-mem search result |

### Live vs Simulated

Default: **live**. Simulated only when live is impossible/destructive.
Record in evidence note: `→ summary [live] (date)` or
`→ summary [simulated: reason] (date)`.
