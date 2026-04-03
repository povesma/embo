# 014: Git Commit & PR Texts — Test Plan

**Status**: Draft
**Tech Design**: [2026-03-29-014-git-commit-pr-texts-tech-design.md](
  2026-03-29-014-git-commit-pr-texts-tech-design.md)
**Created**: 2026-03-29

---

## Story Coverage

### Story 1 — Commit message generation

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 1.1 `/dev:git` reads `git diff --staged` and `git log` | `manual-run-claude` | integration | Claude shows diff stat and log before generating |
| 1.2 Output follows active profile's `git.commit_style` | `manual-run-claude` | integration | conventional style shows `type(scope): subject` format |
| 1.3 Subject ≤72 chars, imperative, no period | `manual-run-claude` | integration | generated subject passes format check |
| 1.4 Body explains why, not what | `manual-run-claude` | integration | body references motivation, not file names |
| 1.5 Message presented for review before commit | `manual-run-user` | integration | user confirms Claude did not auto-commit |
| 1.6 User can accept, edit, or reject | `manual-run-user` | integration | user confirms all three paths work |

### Story 2 — PR description generation

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 2.1 `/dev:git pr` asks for base branch | `manual-run-claude` | integration | Claude prompts "Base branch?" before generating |
| 2.2 Reads `git log <base>..HEAD` and `git diff --stat` | `manual-run-claude` | integration | output references actual commits and changed files |
| 2.3 Output has Summary + Test plan sections | `manual-run-claude` | integration | PR description contains both `## Summary` and `## Test plan` |
| 2.4 Summary is prose, not bullets | `manual-run-claude` | integration | Summary section contains paragraph text |
| 2.5 Test plan bullets specific to actual changes | `manual-run-claude` | integration | checklist items reference real changed behaviour |
| 2.6 Presented for review before `gh pr create` | `manual-run-user` | integration | user confirms no PR created without approval |
| 2.7 Degrades gracefully without `gh` CLI | `manual-run-claude` | integration | without gh, prints description with paste instruction |

### Story 3 — Style configuration via profiles

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 3.1 All four profiles gain `git:` block | `code-only` | — | — |
| 3.2 `/dev:git` reads `git.commit_style` from active profile | `manual-run-claude` | integration | switching to a profile with different style changes output format |
| 3.3 Falls back to `conventional` when `git` block absent | `code-only` | — | — |
| 3.4 `/dev:profile use <name>` shows git style in output | `manual-run-claude` | integration | activation output includes "Git: commit style: conventional" line |

### Story 4 — Custom style definition (v1 deferred)

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 4.1 Profile supports `git.custom_style` block | `code-only` | — | — |
| 4.2 When `commit_style: custom`, uses custom template | `code-only` | — | — |
| 4.3 Missing `custom_style` warns and falls back | `code-only` | — | — |

### Story 5 — Empty staged diff handling

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 5.1 When nothing staged, shows `git status` unstaged files | `manual-run-claude` | integration | Claude lists unstaged files when diff is empty |
| 5.2 Offers to stage all, stage selected, or cancel | `manual-run-user` | integration | user confirms all three options presented |
| 5.3 Stages selected files and proceeds to generation | `manual-run-user` | integration | user confirms staged files appear in diff after selection |

### Story 6 — install.sh + README

| Subtask | Method | Scope | Expected Evidence |
|---------|--------|-------|-------------------|
| 6.1 `git.md` copied by install.sh wildcard | `code-only` | — | — |
| 6.2 `/dev:git` row in README Available Commands table | `code-only` | — | — |

---

## Intentional Gaps

- **All commit/PR generation stories**: Cannot automate verification that
  Claude generates a *good* commit message — quality is subjective and
  requires human review. All generation stories use `manual-run-claude`
  or `manual-run-user`.

- **Story 1.5/1.6 and 2.6 — no auto-commit safety**: Cannot write an
  automated test that proves Claude didn't run `git commit` without
  approval, since the test itself would need to observe Claude's
  behaviour in a live session. Requires `manual-run-user`.

- **Story 5.2/5.3 — interactive staging**: The staging selection flow
  requires a user in the loop to make choices. Not automatable.

- **Story 3.2 — profile style switching**: Requires running `/dev:git`
  twice with different active profiles. Possible with `manual-run-claude`
  but not fully automated since profile switching is a manual step.

- **Story 4 (custom style)**: Entirely `code-only` in v1 — the feature
  is prompt-engineering only with no runtime component to test until
  actually exercised with a real custom profile.

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
