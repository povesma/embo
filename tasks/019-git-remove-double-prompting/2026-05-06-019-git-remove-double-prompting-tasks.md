# 019-git-remove-double-prompting: Tasks

**Status**: Complete
**Created**: 2026-05-06

---

## Problem

`/dev:git` had skill-level AskUserQuestion gates before every
`git commit`, `git push`, and `gh pr create`. Claude Code's harness
already prompts "allow this command?" before every Bash tool call,
making the skill-level gates redundant double-prompts.

## Relevant Files

- `.claude/commands/dev/git.md` — removed skill-level confirmation
  gates for non-destructive commands; kept them for destructive ops

## Tasks

- [X] 1.0 Remove double-prompting from `/dev:git` [3/3]
  - [X] 1.1 Remove AskUserQuestion gate before `git commit` (Step 5). Replace with design-rationale note explaining harness gate is the single approval point, plus fallback instruction if harness ever auto-allows git commands. [verify: code-only]
  - [X] 1.2 Remove AskUserQuestion gates from PR mode: pre-flight checks (Step 2), base-branch prompt (Step 3), PR-create gate (Steps 6+7 collapsed to Step 6). [verify: code-only]
  - [X] 1.3 Add dormant safety checkpoint warehouse as HTML comment at end of file — preserves all four original AskUserQuestion blocks for copy-paste reactivation if the harness gate is ever removed. [verify: code-only]

## Design decisions

- Non-destructive commands (`git commit`, `git push`, `git add`,
  `gh pr create`) rely on the harness permission prompt as the single
  confirmation point.
- Destructive commands (`git push --force`, `git reset`,
  `git rebase`) still get a skill-level AskUserQuestion gate because
  the harness prompt shows the command but not the *context* (why
  it's destructive, what will be lost).
- The dormant checkpoint warehouse (HTML comment) ensures the
  original gate wording isn't lost if it needs to be re-enabled.
